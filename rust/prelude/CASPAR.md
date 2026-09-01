# caspar.js — the Caspar protocol prelude

`prelude/caspar.js` (composed on `import 'caspar.js';`) is a full client for
the [Caspar](https://github.com/cosmopole-org/caspar) node's signed binary
action protocol, written in the guest-JS subset over the reflective bridge:

* **Transports** — `StreamPeerTCP` (default) or `WebSocketPeer`
  (`transport: 'ws'`, auto-selected on web exports where raw TCP does not
  exist; each WS Binary message carries one `u32be(len)||body` frame, matching
  the node's client WS driver). In ws mode the endpoint is `url:` (verbatim —
  how a browser-served client rides its own page origin through an HTTP
  server's `/ws` tunnel, mandatory behind HTTPS single-port hosts) or
  `tls`/`host`/`port` + optional `path`. Both transports pump on a `GTimer`
  (33 ms) into one resumable length-prefixed frame parser (requests carry *no* tag byte;
  responses `0x02` are ACKed with a `u32be(1)|0x01` frame so the server's
  send gate opens; updates `0x01` are fire-and-forget).
* **Auth** — dev `/creatures/login` returns `{user, privateKey}`; the PEM is
  loaded into a Godot `CryptoKey` and every subsequent action is signed
  RSA-SHA256 over the exact payload bytes (`HashingContext` + `Crypto.sign`,
  i.e. PKCS#1 v1.5 — the Caspar node verifies it alongside PSS, see
  caspar `docs/API_REFERENCE.md` "Request signatures").
* **Creature signalling** — `node.signal({creatureId, programId, entityId,
  action, payload}, cb)` wraps the payload in the platform's
  correlation-id envelope, sends `/creatures/signal` (type `pvp`), and routes
  the creature's `creatures/signal/result` update frame back to `cb` by
  correlation id, with timeouts.
* **CaspiNet** — a service-discovery layer for the super-app pattern: given
  a "main" entry creature id + program id (deployed with entity id `main`),
  `discover()` fetches the platform manifest + service registry, and
  `call(service, action, payload, cb)` reaches any registered service by
  name.

## Surface

```js
let node = Caspar.connect({ host, port, transport: 'auto', tls: false,
                            url: '',      // ws mode: 'wss://host/ws' wins
                            path: '',     // ws mode: appended to host:port
                            timeoutMs: 15000, onState: (s) => {} });
node.login('player_one', (res) => {});     // dev login + request signing
node.request('/api/ping', {}, (res) => {});// raw signed action
node.signal({ creatureId, programId, entityId,
              action, payload }, (r) => {});
node.onUpdate((key, data) => {});          // raw update frames
node.transport();                          // 'tcp' | 'ws'
node.close();

let caspi = CaspiNet.open({ node, mainCreatureId, mainProgramId });
caspi.discover((r) => {});                 // -> caspi.services()
caspi.call('games', 'list', {}, (r) => {});
```

## Who uses it

The **CaspiGames** gaming super-app — its client scene, backend creatures,
sample games, e2e/Docker pipeline and docs live in the
[CaspiGames platform repo](https://github.com/cosmopole-org/CaspiGames).

## Tests

`capi/tests/run_caspar_prelude.rs` — the length-prefixed framing round-trips
byte-for-byte (incl. multi-byte UTF-8 and truncation safety), and
`Caspar.connect` opens and pumps a `StreamPeerTCP` (default) and a
`WebSocketPeer` (`transport: 'ws'` mode). The CaspiGames client/system tests
live in that repo (`client/tests/`) and are injected into this crate's tests
directory by its `e2e/test-client.sh`.

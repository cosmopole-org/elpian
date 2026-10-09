# Caspar VM machine → Elpian point signaling (Node.js container example)

This example is intentionally **VM-hosted**, not a standalone network server.

- ✅ Uses **Caspar VM host-imported functions** only.
- ✅ Emits packets via **Caspar point signaling API**.
- ❌ Does **not** expose an HTTP port.
- ❌ Does **not** open WebSocket connections directly.

## Why this shape

Caspar already provides network transport, point membership, and signaling fanout.
A machine program should run inside Caspar VM and call host imports, instead of reimplementing transport.

## Files

- `src/machine-program.js` – machine logic and packet construction.
- `src/host-adapter.js` – host adapter for Caspar VM imports plus local stdout fallback.
- `src/run-machine.js` – example runner that emits bootstrap + init + patch packets.

## Required Caspar VM host imports

When running in Caspar VM mode (`CASPAR_HOST_MODE=vm-imports`), this program expects imported host functions:

- `casparPointSignal(pointId, packet)` (required)
- `casparRegisterMachineWidget(payload)` (optional)

These are read from `globalThis` by `createCasparVmHostFromGlobals()`.

## Packet flow sent by this machine

1. `machine.widget.attached` (engine + integration mode negotiation)
2. `ui.init` (initial Elpian tree)
3. `ui.patch` (incremental updates)

Integration mode options:

- `nextjs_server`
- `streaming_server`
- `fully_client_side`

Scripting language hint:

- `quickjs` for `nextjs_server` and `fully_client_side`
- `n/a` for `streaming_server`

## Local dry-run (stdout mode)

```bash
cd example/caspar-node-machine
npm install
npm start
```

This prints JSON events to stdout (simulating calls that Caspar VM host functions would receive).

## Docker run (still no port exposure)

```bash
docker build -t elpian-caspar-vm-machine .
docker run --rm \
  -e CASPAR_POINT_ID=point-alpha \
  -e CASPAR_MACHINE_ID=machine-1 \
  -e ELPIAN_INTEGRATION_MODE=fully_client_side \
  elpian-caspar-vm-machine
```

## Run against Caspar VM imports

```bash
CASPAR_HOST_MODE=vm-imports node src/run-machine.js
```

In this mode, the runtime must inject host APIs into `globalThis` before program startup.

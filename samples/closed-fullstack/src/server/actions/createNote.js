// An action: returns JSON, may write.
//
// Note the shape of the failure path. There is no `throw` in the subset — and
// no `try`/`catch` to catch one with — so an error is a *value* the caller
// tests. Every SDK call the client makes normalises this into
// `{ ok, result, error }`.

// A short random suffix. `random.next` returns a float in [0, 1).
function randomId() {
  var n = askHost("random.next", []);
  if (n == null) { return "0"; }
  return "" + intOf(n * 1000000);
}

function intOf(x) {
  return x - (x % 1);
}

function createNote(args) {
  if (args == null || args.text == null || args.text == "") {
    return { error: { code: "invalid", message: "a note needs text" } };
  }

  // The key is namespaced by the host under this app. There is no key a guest
  // can construct that reaches another app's state, because the guest never
  // sends an app id.
  //
  // The id mixes the clock with randomness. A timestamp alone is not enough:
  // two notes created in the same millisecond would collide and one would
  // silently overwrite the other. Both `clock` and `randomness` have to be
  // declared in the manifest — without them these calls return null and the id
  // becomes the literal string "note:null" for every note, which is exactly
  // the bug this comment exists to stop you shipping.
  var id = "note:" + now() + "-" + randomId();
  kvSet(id, { id: id, text: args.text, at: now() });

  // Tell the host that renders tagged "notes" are stale. An app can only ever
  // invalidate its own.
  revalidate("notes");

  log("created " + id);
  return { id: id };
}

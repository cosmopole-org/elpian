// A component: RETURNS a UI payload. It never calls `render` — the server
// posture denies that capability, because a component that rendered as a side
// effect could not be cached, could not be tested without a host, and could
// half-render.

function NoteList(args) {
  var keys = kvList("note:");
  var children = [];
  var i = 0;
  while (i < keys.length) {
    var note = kvGet(keys[i]);
    if (note != null) {
      children.push({
        type: "Text",
        props: { text: note.text }
      });
    }
    i = i + 1;
  }

  if (children.length == 0) {
    children.push({ type: "Text", props: { text: "No notes yet." } });
  }

  // Caching is opt-in. Tagged "notes", so the actions above invalidate it; and
  // capped at 60 seconds so a missed revalidation self-corrects rather than
  // serving a stale page forever.
  return ui({ type: "Column", props: {}, children: children }, ["notes"], 60);
}

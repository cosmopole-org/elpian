// The client half. It draws, and it talks to its own server functions — and,
// because this app's posture is `closed`, to nothing else at all.

function view() {
  return {
    type: "Column",
    props: {},
    children: [
      { type: "Text", props: { text: "Notes" } }
    ]
  };
}

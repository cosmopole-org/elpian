function deleteNote(args) {
  if (args == null || args.id == null) {
    return { error: { code: "invalid", message: "which note?" } };
  }
  var removed = kvDelete(args.id);
  revalidate("notes");
  return { removed: removed };
}

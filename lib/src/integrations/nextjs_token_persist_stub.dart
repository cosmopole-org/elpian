// Non-web token persistence: in-memory only (used on IO/native targets where a
// browser localStorage is unavailable). See `nextjs_token_persist_web.dart` for
// the web implementation, selected via conditional import.
final Map<String, String> _mem = <String, String>{};

String? readPersisted(String key) => _mem[key];

void writePersisted(String key, String? value) {
  if (value == null) {
    _mem.remove(key);
  } else {
    _mem[key] = value;
  }
}

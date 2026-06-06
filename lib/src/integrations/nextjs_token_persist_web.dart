// Web token persistence backed by browser localStorage, so a session survives
// page reloads. Selected via conditional import on web targets.
import 'dart:html' as html;

String? readPersisted(String key) => html.window.localStorage[key];

void writePersisted(String key, String? value) {
  if (value == null) {
    html.window.localStorage.remove(key);
  } else {
    html.window.localStorage[key] = value;
  }
}

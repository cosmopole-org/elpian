/// Web GLB/GLTF byte fetcher built on `dart:html`.
///
/// Uses an `XMLHttpRequest` with `responseType: 'arraybuffer'` so the binary
/// payload arrives intact. Subject to the browser's CORS policy — the model
/// host must allow cross-origin reads (the Khronos sample asset CDN does).
library;

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List> fetchModelBytes(String url) async {
  final req = await html.HttpRequest.request(
    url,
    method: 'GET',
    responseType: 'arraybuffer',
  );
  final body = req.response;
  if (body is ByteBuffer) {
    return body.asUint8List();
  }
  if (body is List<int>) {
    return Uint8List.fromList(body);
  }
  throw StateError('Unexpected response type for $url: ${body.runtimeType}');
}

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 브라우저에서 파일을 내려받게 한다 (Blob + a[download])
///
/// 웹 앱은 파일을 직접 저장할 수 없어서, 임시 주소를 만들어 링크를 누른 것처럼 한다.
void downloadBytes(Uint8List bytes, String filename, {String mimeType = 'application/pdf'}) {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // 바로 해제하면 일부 브라우저가 내려받기를 시작하기 전에 주소가 사라진다
  Future<void>.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
}

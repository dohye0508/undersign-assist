import 'package:flutter/foundation.dart';

import 'document_photo.dart';
import 'recognized_document.dart';

/// 문서 한 장을 다루는 동안 네 단계가 함께 보는 상태.
/// 읽기가 결과를 채우면 판단, 쓰기, 서명이 그것을 이어받는다.
class DocumentSession extends ChangeNotifier {
  DocumentSession(this.photo);

  final DocumentPhoto photo;

  RecognizedDocument? _recognized;
  RecognizedDocument? get recognized => _recognized;

  set recognized(RecognizedDocument? value) {
    _recognized = value;
    notifyListeners();
  }
}

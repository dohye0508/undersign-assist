import 'dart:typed_data';

/// 사용자가 카메라로 찍거나 폴더에서 고른 종이 문서 사진. 모든 기능의 입력이다.
class DocumentPhoto {
  const DocumentPhoto({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

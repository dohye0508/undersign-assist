import 'dart:typed_data';

import 'recognized_document.dart';

/// 문서에서 사용자가 채워야 하는 칸 하나 (예: 학생 성명, 보호자 서명).
/// 쓰기와 서명은 하는 일이 같아서(패드에 써서 문서 자리에 넣기) 한 모양으로 다룬다.
class FillTarget {
  const FillTarget({
    required this.id,
    required this.label,
    required this.page,
    required this.rect,
    required this.isSignature,
  });

  /// 같은 문서 안에서 칸을 구분하는 값 (예: "p0-l12-성명")
  final String id;

  /// 들려줄 이름 (예: "학생 성명", "보호자 서명")
  final String label;

  /// 몇 번째 페이지인지 (0부터)
  final int page;

  /// 글씨가 들어갈 자리. 그 페이지 사진의 픽셀 좌표
  final Box rect;

  /// 서명·도장 칸이면 true, 글씨(이름, 주소 등) 칸이면 false
  final bool isSignature;
}

/// 사용자가 채운 칸: 어떤 칸에, 패드에 쓴 글씨(투명 배경 PNG)
class FilledInk {
  const FilledInk({required this.target, required this.png});

  final FillTarget target;
  final Uint8List png;
}

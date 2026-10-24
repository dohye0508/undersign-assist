import '../../models/fill.dart';

/// 칸의 종류. [FillTarget]은 공유 모델이라 필드를 늘리지 않고 이름과 [FillTarget.isSignature]에서 끌어낸다.
///
/// - text: 글씨를 쓰는 칸 (성명, 주소, 날짜 …)
/// - signature: 서명·도장 칸
/// - check: "□예 □아니요"처럼 하나를 골라 표시하는 칸. 이름이 "동의 여부"로 끝난다
enum FillKind { text, signature, check }

extension FillTargetKind on FillTarget {
  FillKind get kind {
    if (label.endsWith('동의 여부')) return FillKind.check;
    return isSignature ? FillKind.signature : FillKind.text;
  }
}

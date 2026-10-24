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

  /// 날짜 칸인가 ("2026년 월 일" 줄에서 찾은 칸). id 꼬리가 `-날짜-md` 또는 `-날짜-ymd`
  bool get isDate => id.contains('-날짜-');

  /// 날짜 칸에서 연도까지 써야 하는가. 연도가 인쇄돼 있지 않으면("년 월 일") id가 `-ymd`로 끝난다.
  /// 모델에 필드를 더하지 않으려고 id에 실어 둔다 ([findFillTargets]가 붙인다)
  bool get dateNeedsYear => id.endsWith('-ymd');

  /// 진행 동그라미 아래에 쓰는 짧은 이름: 서명 → "서명", 동의 여부 → "동의", 글씨 칸 → 이름의 마지막 낱말(성명, 날짜, 주소 …)
  String get shortName {
    switch (kind) {
      case FillKind.signature:
        return '서명';
      case FillKind.check:
        return '동의';
      case FillKind.text:
        final words = label.trim().split(RegExp(r'\s+'));
        return words.isEmpty ? label : words.last;
    }
  }
}

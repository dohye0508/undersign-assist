import '../../models/judgement.dart';

/// 검토하지 못한 문서나 읽지 못한 값을 "문제 없음"으로 안내하지 않는다.
String judgementConclusion(Judgement judgement) {
  final caution = judgement.counts['caution'] ?? 0;
  final missing = judgement.counts['missing'] ?? 0;
  if (caution + missing > 0) return '확인할 곳 $caution개, 빠진 것 $missing개예요.';
  if (judgement.findings.any((f) => f.ruleId == 'unsupported_judgement')) {
    return '이 문서의 자동 검토를 완료하지 못했어요.';
  }
  if (judgement.findings.any(
    (f) => f.ruleId.startsWith('form_') && f.ruleId.endsWith('_unread'),
  )) {
    return '읽지 못한 항목이 있어요. 원문을 확인해 주세요.';
  }
  if (judgement.findings.any((f) => f.level == 'info')) {
    return '확인 안내가 있어요. 원문과 함께 살펴보세요.';
  }
  return '특별히 확인할 것이 없어요.';
}

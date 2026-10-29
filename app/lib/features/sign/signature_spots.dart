import '../../models/recognized_document.dart';

/// 문서에서 서명이 필요한 곳 한 군데
class SignatureSpot {
  const SignatureSpot({required this.label, required this.line, required this.page, required this.text});

  /// 들려줄 이름 (예: "근로자 줄", 여러 페이지면 "2페이지 근로자 줄")
  final String label;

  /// 읽기 결과 blocks에서 몇 번째 줄인지
  final int line;

  /// 몇 번째 페이지인지 (0부터)
  final int page;

  /// 그 줄의 원문
  final String text;
}

/// 읽기 결과에서 "서명", "(인)", "날인"이 있는 줄을 찾는다 (계획서: 빈칸 검출 로직 재사용).
/// 백엔드를 부르지 않고 앱에서 바로 한다.
List<SignatureSpot> findSignatureSpots(RecognizedDocument document) {
  if (document.needsReview) return [];
  final keyword = RegExp(r'서\s*명|\(\s*인\s*\)|날\s*인');
  // 본문 문장 속 "서명하다" 같은 말은 서명란이 아니다
  final sentence = RegExp(r'서\s*명\s*(하|합|함|을|이|한|할|해)');

  final multiPage = document.pages.length > 1;
  final spots = <SignatureSpot>[];
  for (final (i, block) in document.blocks.indexed) {
    final text = block.text.trim();
    if (!keyword.hasMatch(text) || sentence.hasMatch(text)) continue;
    // 줄 맨 앞의 주체(예: 근로자, 사업주, 보호자)로 어느 칸인지 말한다.
    // OCR 띄어쓰기는 믿기 어려워("사업 주") 공백을 지우고, 첫 칸 이름(상호, 주소, 성명…) 앞까지를 쓴다
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    final owner = RegExp(r'^([가-힣]{1,6}?)(상호|주소|성명|대표자?|이름|연락처|[:：(]|서명)').firstMatch(compact)?.group(1);
    // 주체 없이 칸 이름으로 시작하는 줄(예: "성명: (서명)")은 몇 번째 줄인지로 말한다
    final generic = owner == null || RegExp(r'^(성명|이름|주소|상호|대표자?|연락처)$').hasMatch(owner);
    final name = generic ? '${i + 1}번째 줄' : '$owner 줄';
    final label = multiPage ? '${block.page + 1}페이지 $name' : name;
    spots.add(SignatureSpot(label: label, line: i, page: block.page, text: text));
  }
  return spots;
}

/// "서명이 필요한 곳은 2곳이에요. 첫째, 사업주 줄. 둘째, 근로자 줄."
String describeSignatureSpots(List<SignatureSpot> spots) {
  if (spots.isEmpty) return '서명란을 찾지 못했어요. 서명할 곳이 사진에 들어오게 다시 찍어 주세요.';
  const ordinals = ['첫째', '둘째', '셋째', '넷째', '다섯째'];
  final parts = [
    for (final (i, spot) in spots.indexed) '${i < ordinals.length ? ordinals[i] : '${i + 1}번째'}, ${spot.label}.',
  ];
  return '서명이 필요한 곳은 ${spots.length}곳이에요. ${parts.join(' ')}';
}

/// 분석 요약에 붙일 말: "서명이 필요한 페이지는 1페이지와 3페이지예요."
String describeSignaturePages(List<SignatureSpot> spots) {
  if (spots.isEmpty) return '서명란은 찾지 못했어요.';
  final pages = {for (final s in spots) s.page + 1}.toList()..sort();
  final names = pages.map((p) => '$p페이지').toList();
  final joined = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')}와 ${names.last}';
  return '서명이 필요한 페이지는 $joined예요.';
}

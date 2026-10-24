// 내 정보(생년월일·전화번호·주소)를 저장하고 연습 낱말로 나누는 순수 함수. 화면·저장소와 무관해서 `flutter test`로 시험한다.

/// 생년월일을 "2008년 3월 15일" 꼴로 맞춘다.
/// 숫자만 들어오면(20080315, 2008-03-15, 2008.3.15, 2008/3/15, "2008년 03월 15일") 모두 같은 꼴로 바꾼다.
/// 숫자로 읽을 수 없으면 입력을 다듬어서(앞뒤 공백 제거) 그대로 둔다. 비어 있으면 빈 문자열
String normalizeBirth(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  final digits = RegExp(r'\d+').allMatches(text).map((m) => m.group(0)!).toList();
  final joined = digits.join();
  // 8자리가 한 덩어리로 들어온 경우 (20080315)
  if (digits.length == 1 && joined.length == 8) {
    return _formatYmd(int.parse(joined.substring(0, 4)), int.parse(joined.substring(4, 6)), int.parse(joined.substring(6, 8)), text);
  }
  // 연·월·일 세 덩어리 (2008-03-15, 2008.3.15, 2008년 3월 15일)
  if (digits.length == 3 && digits[0].length == 4) {
    return _formatYmd(int.parse(digits[0]), int.parse(digits[1]), int.parse(digits[2]), text);
  }
  return text;
}

String _formatYmd(int year, int month, int day, String fallback) {
  if (year < 1900 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return fallback;
  return '$year년 $month월 $day일';
}

/// "2008년 3월 15일"을 연·월·일 글자 세 개로. 꼴이 다르면 빈 목록
List<String> splitBirth(String birth) {
  final m = RegExp(r'^(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일$').firstMatch(birth.trim());
  if (m == null) return const [];
  return [m.group(1)!, m.group(2)!, m.group(3)!];
}

/// 전화번호는 숫자와 - 만 남긴다. 숫자만 들어온 10~11자리는 - 를 넣어 준다(01012345678 → 010-1234-5678)
String normalizePhone(String input) {
  final kept = input.replaceAll(RegExp(r'[^0-9\-]'), '');
  if (kept.isEmpty) return '';
  if (!kept.contains('-')) {
    if (kept.length == 11) return '${kept.substring(0, 3)}-${kept.substring(3, 7)}-${kept.substring(7)}';
    if (kept.length == 10) return '${kept.substring(0, 3)}-${kept.substring(3, 6)}-${kept.substring(6)}';
  }
  // 겹친 - 와 앞뒤 - 는 정리
  return kept.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

/// 전화번호를 - 로 나눈 덩어리 ("010", "1234", "5678")
List<String> splitPhone(String phone) => phone.split('-').where((p) => p.isNotEmpty).toList();

/// 주소를 띄어쓰기 단위로 나눈다 ("서울시 강남구 테헤란로 12" → 4개)
List<String> splitAddress(String address) => address.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

/// "첫째, 둘째 …" 대신 쓰는 "1번째" 식 순서말
String ordinal(int index) => '${index + 1}번째';

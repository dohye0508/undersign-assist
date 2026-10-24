import '../../models/fill.dart';
import '../practice/score_store.dart';
import 'fill_kind.dart';

/// 쓰고 서명하기의 글씨 칸에 깔아 주는 **회색 보조 글씨**.
///
/// 받아쓰기(글씨 연습)에서 등록한 내 정보(이름·주소·생년월일·연락처, [ScoreStore])를 그 칸에 맞게 골라
/// 연한 회색으로 보여 주고, 사용자는 그 위에 따라 쓴다. 화면용 레이어일 뿐이라 쓴 글씨에는 들어가지 않고,
/// 진동·소리 안내도 없다(받아쓰기의 거리 진동은 쓰지 않는다).
///
/// 순수 함수라 `flutter test`로 시험한다. 날짜는 [now]를 넣어 고정할 수 있다.
class GuideText {
  const GuideText(this.text, this.spoken);

  /// 칸에 깔 글자
  final String text;

  /// 칸 안내 끝에 덧붙여 말할 한 문장 ("등록한 이름 김이름이 회색으로 보여요. 따라 써도 돼요.")
  final String spoken;
}

/// 이름류 칸 이름. 서명 칸은 [FillKind.signature]라 여기 오지 않는다
const _nameWords = ['성명', '이름', '서명자', '작성자'];
const _addressWords = ['주소'];
const _birthWords = ['생년월일'];
const _phoneWords = ['연락처', '전화', '휴대폰', '핸드폰'];

/// 본인이 아닌 주체. 이 말이 칸 이름에 붙어 있으면 내 정보를 깔지 않는다 (엉뚱한 사람 이름이 들어가면 안 된다).
/// 학생·근로자·신청자·지원자·본인 등은 본인으로 본다
const _otherOwners = [
  '보호자', '학부모', '법정대리인', '사업주', '사용자', '고용주', '대표', '회사', '상대방', //
  '임대인', '매도인', '연대보증인', '보증인', '대리인', '수임인', '담당자', '담임', '교사', //
  '아버지', '어머니', '부모', '배우자', '자녀',
];

/// 한 글자 주체는 낱말 단위로만 본다 ("을"이 "마을"에 걸리지 않게)
const _otherOwnerTokens = ['갑', '을'];

/// 라벨이 본인이 아닌 주체의 칸인가
bool isOtherOwner(String label) {
  if (_otherOwners.any(label.contains)) return true;
  final tokens = label.split(RegExp(r'[\s()·,/]+'));
  return tokens.any(_otherOwnerTokens.contains);
}

/// "2008년 3월 15일", "2008.3.15", "2008-03-15", "20080315" 꼴에서 연·월·일을 뽑는다. 못 읽으면 null
({int year, int month, int day})? parseBirth(String birth) {
  final s = birth.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'(\d{4})\D*(\d{1,2})\D*(\d{1,2})').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return (year: y, month: mo, day: d);
}

/// [target]에 깔 보조 글씨. 글씨 칸이 아니거나(서명·체크), 맞는 등록 값이 없으면 null.
///
/// - 성명·이름 → [ScoreStore.name], 주소 → [ScoreStore.address], 생년월일 → [ScoreStore.birth], 연락처·전화 → [ScoreStore.phone].
///   단 칸 이름에 보호자·학부모·법정대리인·사업주·대표 같은 **본인이 아닌 주체**가 있으면 null.
/// - 날짜 칸(id 꼬리 `-연도`/`-월`/`-일`)은 **오늘 날짜**의 그 부분 숫자 (계약서 날짜는 보통 작성일).
///   칸 이름에 "생년월일"이 있으면 등록한 생년월일에서 뽑는다
GuideText? guideFor(FillTarget target, ScoreStore store, {DateTime? now}) {
  if (target.kind != FillKind.text) return null;
  final label = target.label;

  if (target.datePart case final part?) {
    if (label.contains('생년월일')) {
      if (isOtherOwner(label)) return null;
      final b = parseBirth(store.birth);
      if (b == null) return null;
      final v = switch (part) { '연도' => b.year, '월' => b.month, _ => b.day };
      return GuideText('$v', '등록한 생년월일의 $part $v${_iGa('$v')} 회색으로 보여요. 따라 써도 돼요.');
    }
    final today = now ?? DateTime.now();
    final v = switch (part) { '연도' => today.year, '월' => today.month, _ => today.day };
    return GuideText('$v', '오늘 날짜 $v${_iGa('$v')} 회색으로 보여요. 따라 써도 돼요.');
  }

  if (isOtherOwner(label)) return null;

  if (_nameWords.any(label.contains)) {
    return _value(store.name, (v) => '등록한 이름 $v${_iGa(v)} 회색으로 보여요. 따라 써도 돼요.');
  }
  if (_addressWords.any(label.contains)) {
    return _value(store.address, (_) => '등록한 주소가 회색으로 보여요. 따라 써도 돼요.');
  }
  if (_birthWords.any(label.contains)) {
    return _value(store.birth, (_) => '등록한 생년월일이 회색으로 보여요. 따라 써도 돼요.');
  }
  if (_phoneWords.any(label.contains)) {
    return _value(store.phone, (_) => '등록한 연락처가 회색으로 보여요. 따라 써도 돼요.');
  }
  return null;
}

/// 깔 글자만 (시험·간단한 호출용)
String? guideTextFor(FillTarget target, ScoreStore store, {DateTime? now}) => guideFor(target, store, now: now)?.text;

GuideText? _value(String raw, String Function(String) spoken) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  return GuideText(v, spoken(v));
}

/// 숫자·한글 뒤 이/가. 숫자는 마지막 자리의 우리말 받침으로 본다 (0,1,3,6,7,8 받침 있음)
String _iGa(String word) {
  if (word.isEmpty) return '가';
  final last = word.codeUnitAt(word.length - 1);
  if (last >= 0x30 && last <= 0x39) {
    return const {0x30, 0x31, 0x33, 0x36, 0x37, 0x38}.contains(last) ? '이' : '가';
  }
  if (last < 0xAC00 || last > 0xD7A3) return '이';
  return (last - 0xAC00) % 28 == 0 ? '가' : '이';
}

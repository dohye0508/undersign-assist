import 'hangul.dart';
import 'profile_format.dart';

/// 연습 종류. 점수판의 막대 네 개와 같다
enum PracticeKind {
  consonant('자음'),
  vowel('모음'),
  syllable('글자'),
  word('낱말');

  const PracticeKind(this.label);

  final String label;
}

/// 쓸 글자 하나(또는 낱말 하나)
class PracticeItem {
  const PracticeItem(this.kind, this.text, {this.intro = ''});

  final PracticeKind kind;
  final String text;

  /// 시작할 때 들려줄 설명 (비어 있으면 글자에서 만든다)
  final String intro;

  /// 점수를 저장할 때 쓰는 이름표
  String get key => '${kind.name}:$text';

  /// "기역"처럼 소리 내어 부르는 이름
  String get spokenName {
    switch (kind) {
      case PracticeKind.consonant:
      case PracticeKind.vowel:
        return jamoName(text);
      case PracticeKind.syllable:
      case PracticeKind.word:
        return text;
    }
  }

  /// 처음에 들려줄 말
  String get speech {
    switch (kind) {
      case PracticeKind.consonant:
      case PracticeKind.vowel:
        return intro;
      case PracticeKind.syllable:
        return describeSyllable(text);
      case PracticeKind.word:
        return intro.isNotEmpty ? intro : '낱말 $text. 보조선을 따라 한 줄로 써 보세요.';
    }
  }
}

/// 자음 14개와 쓰는 법
const consonantItems = <PracticeItem>[
  PracticeItem(PracticeKind.consonant, 'ㄱ', intro: '기역. 가로로 긋고, 끝에서 아래로 내려 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㄴ', intro: '니은. 위에서 아래로 내려 긋고, 끝에서 오른쪽으로 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㄷ', intro: '디귿. 가로로 긋고, 왼쪽 끝에서 아래로 내려 긋고, 그 끝에서 오른쪽으로 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㄹ', intro: '리을. 가로로 긋고, 오른쪽 끝에서 아래로 내린 뒤 왼쪽으로 긋고, 다시 아래로 내려 오른쪽으로 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅁ', intro: '미음. 네모 모양이에요. 왼쪽 위에서 아래로 내리고, 오른쪽으로 긋고, 위로 올리고, 왼쪽으로 닫습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅂ', intro: '비읍. 세로선 두 개를 긋고, 가운데와 아래에 가로선 두 개를 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅅ', intro: '시옷. 위에서 왼쪽 아래로 긋고, 다시 위에서 오른쪽 아래로 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅇ', intro: '이응. 동그라미를 한 번에 그립니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅈ', intro: '지읒. 가로선을 긋고, 그 아래에 시옷을 씁니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅊ', intro: '치읓. 위에 짧은 선을 긋고, 가로선과 시옷을 씁니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅋ', intro: '키읔. 기역을 쓰고, 가운데에 가로선을 하나 더 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅌ', intro: '티읕. 디귿을 쓰고, 가운데에 가로선을 하나 더 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅍ', intro: '피읖. 위아래에 가로선을 긋고, 양쪽에 세로선 두 개를 긋습니다.'),
  PracticeItem(PracticeKind.consonant, 'ㅎ', intro: '히읗. 위에 짧은 가로선과 점을 쓰고, 아래에 이응을 씁니다.'),
];

/// 모음 10개와 쓰는 법
const vowelItems = <PracticeItem>[
  PracticeItem(PracticeKind.vowel, 'ㅏ', intro: '아. 위에서 아래로 세로선을 긋고, 가운데에서 오른쪽으로 짧게 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅑ', intro: '야. 세로선을 긋고, 오른쪽으로 짧은 선을 위아래로 두 개 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅓ', intro: '어. 세로선을 긋고, 가운데에서 왼쪽으로 짧게 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅕ', intro: '여. 세로선을 긋고, 왼쪽으로 짧은 선을 위아래로 두 개 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅗ', intro: '오. 가로선을 긋고, 가운데에서 위로 짧게 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅛ', intro: '요. 가로선을 긋고, 위로 짧은 선을 왼쪽 오른쪽에 두 개 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅜ', intro: '우. 가로선을 긋고, 가운데에서 아래로 짧게 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅠ', intro: '유. 가로선을 긋고, 아래로 짧은 선을 왼쪽 오른쪽에 두 개 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅡ', intro: '으. 가로선 하나를 긋습니다.'),
  PracticeItem(PracticeKind.vowel, 'ㅣ', intro: '이. 세로선 하나를 긋습니다.'),
];

/// 글자: 받침 없는 기본 글자 14개, 이어서 받침 있는 글자 8개
final syllableItems = <PracticeItem>[
  for (final c in '가나다라마바사아자차카타파하'.split('')) PracticeItem(PracticeKind.syllable, c),
  for (final c in '강눈달밤집옷학힘'.split('')) PracticeItem(PracticeKind.syllable, c),
];

/// 낱말 묶음
enum WordGroup {
  /// 등록한 내 정보: 이름, 주소(띄어쓰기 단위), 생년월일(연·월·일), 전화번호(- 단위)
  myInfo('내 정보'),

  /// 계약서 날짜 칸: 오늘 날짜와 생년월일의 연·월·일 (숫자 연습)
  date('날짜'),
  contract('계약서 낱말'),
  general('일반 낱말');

  const WordGroup(this.label);

  final String label;
}

const contractWords = ['동의', '확인', '서명', '예', '아니요', '성명', '주소', '생년월일', '전화번호', '연락처'];
const generalWords = ['솔숲', '하늘', '나무', '바다', '학교', '가족', '사랑', '친구'];

/// 등록한 내 정보. 비어 있는 칸은 빈 문자열
class ProfileInfo {
  const ProfileInfo({this.name = '', this.address = '', this.birth = '', this.phone = ''});

  final String name;
  final String address;

  /// "2008년 3월 15일" 꼴
  final String birth;

  /// "010-1234-5678" 꼴
  final String phone;

  bool get isEmpty => name.isEmpty && address.isEmpty && birth.isEmpty && phone.isEmpty;
}

PracticeItem _word(String text, String what) =>
    PracticeItem(PracticeKind.word, text, intro: '$what, $text. 보조선을 따라 한 줄로 써 보세요.');

/// 내 정보 낱말: 긴 것은 한 칸에 들어갈 만큼 나눈다. 무엇을 쓰는지 먼저 말한다 ("주소의 2번째 낱말, 강남구")
List<PracticeItem> _profileItems(ProfileInfo p) {
  final out = <PracticeItem>[];
  if (p.name.isNotEmpty) out.add(_word(p.name, '이름'));
  final address = splitAddress(p.address);
  for (var i = 0; i < address.length; i++) {
    out.add(_word(address[i], address.length == 1 ? '주소' : '주소의 ${ordinal(i)} 낱말'));
  }
  out.addAll(_dateItems(splitBirth(p.birth), '생년월일'));
  final phone = splitPhone(p.phone);
  for (var i = 0; i < phone.length; i++) {
    out.add(_word(phone[i], phone.length == 1 ? '전화번호' : '전화번호의 ${ordinal(i)} 덩어리'));
  }
  return out;
}

/// [ymd]가 연·월·일 세 개면 "날짜의 연도, 2026"처럼 칸 세 개
List<PracticeItem> _dateItems(List<String> ymd, String what) {
  if (ymd.length != 3) return const [];
  return [
    _word(ymd[0], '$what의 연도'),
    _word(ymd[1], '$what의 월'),
    _word(ymd[2], '$what의 일'),
  ];
}

/// [group]의 낱말들. 내 정보는 [profile]에 등록된 것만, 비어 있으면 빈 목록.
/// 날짜는 [today](없으면 지금)의 연·월·일, 생년월일이 있으면 그것도
List<PracticeItem> wordItems(WordGroup group, {ProfileInfo profile = const ProfileInfo(), DateTime? today}) {
  switch (group) {
    case WordGroup.myInfo:
      return _profileItems(profile);
    case WordGroup.date:
      final now = today ?? DateTime.now();
      return [
        ..._dateItems(['${now.year}', '${now.month}', '${now.day}'], '오늘 날짜'),
        ..._dateItems(splitBirth(profile.birth), '생년월일'),
      ];
    case WordGroup.contract:
      return [for (final w in contractWords) PracticeItem(PracticeKind.word, w)];
    case WordGroup.general:
      return [for (final w in generalWords) PracticeItem(PracticeKind.word, w)];
  }
}

List<PracticeItem> itemsFor(PracticeKind kind) {
  switch (kind) {
    case PracticeKind.consonant:
      return consonantItems;
    case PracticeKind.vowel:
      return vowelItems;
    case PracticeKind.syllable:
      return syllableItems;
    case PracticeKind.word:
      return const [];
  }
}

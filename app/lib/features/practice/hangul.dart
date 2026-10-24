import 'dart:ui';

/// 한글 음절 분해와 "어디에 무엇을 쓰는지" 말하기. 순수 함수만 있다 (화면·글꼴과 무관).

const _choseong = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
const _jungseong = [
  'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ', //
  'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
];
const _jongseong = [
  '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', //
  'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

/// 자음 이름 (받침에 쓰이는 겹받침은 [_compound]로 풀어서 부른다)
const _consonantNames = {
  'ㄱ': '기역', 'ㄲ': '쌍기역', 'ㄴ': '니은', 'ㄷ': '디귿', 'ㄸ': '쌍디귿', 'ㄹ': '리을', 'ㅁ': '미음', //
  'ㅂ': '비읍', 'ㅃ': '쌍비읍', 'ㅅ': '시옷', 'ㅆ': '쌍시옷', 'ㅇ': '이응', 'ㅈ': '지읒', 'ㅉ': '쌍지읒', //
  'ㅊ': '치읓', 'ㅋ': '키읔', 'ㅌ': '티읕', 'ㅍ': '피읖', 'ㅎ': '히읗',
};

const _vowelNames = {
  'ㅏ': '아', 'ㅐ': '애', 'ㅑ': '야', 'ㅒ': '얘', 'ㅓ': '어', 'ㅔ': '에', 'ㅕ': '여', 'ㅖ': '예', 'ㅗ': '오', //
  'ㅘ': '와', 'ㅙ': '왜', 'ㅚ': '외', 'ㅛ': '요', 'ㅜ': '우', 'ㅝ': '워', 'ㅞ': '웨', 'ㅟ': '위', 'ㅠ': '유', //
  'ㅡ': '으', 'ㅢ': '의', 'ㅣ': '이',
};

const _compound = {
  'ㄳ': ['ㄱ', 'ㅅ'], 'ㄵ': ['ㄴ', 'ㅈ'], 'ㄶ': ['ㄴ', 'ㅎ'], 'ㄺ': ['ㄹ', 'ㄱ'], 'ㄻ': ['ㄹ', 'ㅁ'], //
  'ㄼ': ['ㄹ', 'ㅂ'], 'ㄽ': ['ㄹ', 'ㅅ'], 'ㄾ': ['ㄹ', 'ㅌ'], 'ㄿ': ['ㄹ', 'ㅍ'], 'ㅀ': ['ㄹ', 'ㅎ'], 'ㅄ': ['ㅂ', 'ㅅ'],
};

/// 세로로 긴 모음은 오른쪽에, 가로로 긴 모음은 아래에, 둘이 합쳐진 모음은 오른쪽과 아래에 놓인다
enum VowelShape { vertical, horizontal, both }

/// 음절 하나를 초성·중성·종성으로 나눈 것
class Syllable {
  const Syllable(this.char, this.cho, this.jung, this.jong);

  final String char;
  final String cho;
  final String jung;

  /// 받침이 없으면 빈 문자열
  final String jong;

  bool get hasJong => jong.isNotEmpty;

  VowelShape get shape {
    const vertical = {'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅣ'};
    const horizontal = {'ㅗ', 'ㅛ', 'ㅜ', 'ㅠ', 'ㅡ'};
    if (vertical.contains(jung)) return VowelShape.vertical;
    if (horizontal.contains(jung)) return VowelShape.horizontal;
    return VowelShape.both;
  }
}

/// 한글 음절이면 나눠서, 아니면 null
Syllable? decompose(String char) {
  if (char.isEmpty) return null;
  final code = char.runes.first - 0xAC00;
  if (code < 0 || code > 11171) return null;
  return Syllable(
    String.fromCharCode(char.runes.first),
    _choseong[code ~/ 588],
    _jungseong[(code % 588) ~/ 28],
    _jongseong[code % 28],
  );
}

/// 문자열 전체가 한글 음절이면 true (이름 등록 검사용)
bool isAllHangul(String text) {
  if (text.isEmpty) return false;
  return text.runes.every((r) => r >= 0xAC00 && r <= 0xD7A3);
}

/// 자모 하나를 소리 내어 부르는 이름. 모르는 글자면 그대로 돌려준다
String jamoName(String jamo) {
  final parts = _compound[jamo];
  if (parts != null) return parts.map(jamoName).join(' ');
  return _consonantNames[jamo] ?? _vowelNames[jamo] ?? jamo;
}

bool _hasBatchim(String text) {
  if (text.isEmpty) return false;
  final code = text.runes.last - 0xAC00;
  if (code < 0 || code > 11171) return false;
  return code % 28 != 0;
}

/// "을/를"
String eulReul(String text) => _hasBatchim(text) ? '을' : '를';

/// "이/가"
String iGa(String text) => _hasBatchim(text) ? '이' : '가';

/// "이에요/예요"
String ieyo(String text) => _hasBatchim(text) ? '이에요' : '예요';

/// "가. 왼쪽에 기역, 오른쪽에 아를 씁니다." 처럼 음절의 자리 배치를 말해 준다
String describeSyllable(String char) {
  final s = decompose(char);
  if (s == null) return char;
  final cho = jamoName(s.cho);
  final jung = jamoName(s.jung);
  final jong = jamoName(s.jong);
  final String layout;
  switch (s.shape) {
    case VowelShape.vertical:
      layout = s.hasJong
          ? '위 왼쪽에 $cho, 오른쪽에 $jung, 아래에 $jong'
          : '왼쪽에 $cho, 오른쪽에 $jung';
    case VowelShape.horizontal:
      layout = s.hasJong
          ? '위에 $cho, 가운데에 $jung, 맨 아래에 $jong'
          : '위에 $cho, 아래에 $jung';
    case VowelShape.both:
      layout = s.hasJong
          ? '위 왼쪽에 $cho, 오른쪽과 가운데 아래에 $jung, 맨 아래에 $jong'
          : '위 왼쪽에 $cho, 오른쪽과 아래에 $jung';
  }
  final last = s.hasJong ? jong : jung;
  return '${s.char}. $layout${eulReul(last)} 씁니다.';
}

/// 음절 안의 한 부분 (초성·중성·종성)
class SyllablePart {
  const SyllablePart(this.name, this.unit);

  /// "기역 부분"처럼 말할 때 쓰는 이름
  final String name;

  /// 음절 글씨 상자 안의 위치. 가로·세로 모두 0~1
  final Rect unit;
}

/// 음절을 부분별로 나눈 대략의 칸. 글꼴마다 비율이 조금 달라서 근사다
List<SyllablePart> syllableParts(String char) {
  final s = decompose(char);
  if (s == null) return const [];
  final cho = jamoName(s.cho);
  final jung = jamoName(s.jung);
  final jong = jamoName(s.jong);
  switch (s.shape) {
    case VowelShape.vertical:
      final bottom = s.hasJong ? 0.65 : 1.0;
      return [
        SyllablePart(cho, Rect.fromLTRB(0, 0, 0.55, bottom)),
        SyllablePart(jung, Rect.fromLTRB(0.5, 0, 1, bottom)),
        if (s.hasJong) SyllablePart(jong, Rect.fromLTRB(0, 0.65, 1, 1)),
      ];
    case VowelShape.horizontal:
      if (s.hasJong) {
        return [
          SyllablePart(cho, Rect.fromLTRB(0, 0, 1, 0.35)),
          SyllablePart(jung, Rect.fromLTRB(0, 0.3, 1, 0.65)),
          SyllablePart(jong, Rect.fromLTRB(0, 0.65, 1, 1)),
        ];
      }
      return [
        SyllablePart(cho, Rect.fromLTRB(0, 0, 1, 0.5)),
        SyllablePart(jung, Rect.fromLTRB(0, 0.5, 1, 1)),
      ];
    case VowelShape.both:
      final bottom = s.hasJong ? 0.65 : 1.0;
      return [
        SyllablePart(cho, Rect.fromLTRB(0, 0, 0.5, 0.5)),
        SyllablePart(jung, Rect.fromLTRB(0, 0.3, 1, bottom)),
        if (s.hasJong) SyllablePart(jong, Rect.fromLTRB(0, 0.65, 1, 1)),
      ];
  }
}

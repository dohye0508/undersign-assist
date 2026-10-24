import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/hangul.dart';

void main() {
  group('decompose', () {
    test('받침 없는 글자', () {
      final s = decompose('가')!;
      expect([s.cho, s.jung, s.jong], ['ㄱ', 'ㅏ', '']);
      expect(s.hasJong, isFalse);
      expect(s.shape, VowelShape.vertical);
    });

    test('받침 있는 글자', () {
      final s = decompose('강')!;
      expect([s.cho, s.jung, s.jong], ['ㄱ', 'ㅏ', 'ㅇ']);
      expect(s.hasJong, isTrue);
    });

    test('모음 모양: 가로, 둘이 합쳐진 모음', () {
      expect(decompose('고')!.shape, VowelShape.horizontal);
      expect(decompose('과')!.shape, VowelShape.both);
    });

    test('한글 음절이 아니면 null', () {
      expect(decompose('a'), isNull);
      expect(decompose('ㄱ'), isNull);
      expect(decompose(''), isNull);
    });

    test('이름 검사', () {
      expect(isAllHangul('김이름'), isTrue);
      expect(isAllHangul('kim'), isFalse);
      expect(isAllHangul('김 이름'), isFalse);
      expect(isAllHangul(''), isFalse);
    });
  });

  group('말하기', () {
    test('자모 이름', () {
      expect(jamoName('ㄱ'), '기역');
      expect(jamoName('ㅏ'), '아');
      expect(jamoName('ㄳ'), '기역 시옷');
    });

    test('을/를', () {
      expect(eulReul('이응'), '을');
      expect(eulReul('아'), '를');
    });

    test('가: 왼쪽에 기역, 오른쪽에 아', () {
      expect(describeSyllable('가'), '가. 왼쪽에 기역, 오른쪽에 아를 씁니다.');
    });

    test('강: 받침이 아래에', () {
      expect(describeSyllable('강'), '강. 위 왼쪽에 기역, 오른쪽에 아, 아래에 이응을 씁니다.');
    });

    test('고: 가로 모음은 아래에', () {
      expect(describeSyllable('고'), '고. 위에 기역, 아래에 오를 씁니다.');
    });
  });

  group('syllableParts', () {
    test('강은 초성·중성·종성 세 부분', () {
      final parts = syllableParts('강');
      expect(parts.map((p) => p.name), ['기역', '아', '이응']);
    });

    test('가는 두 부분이고 칸이 상자 안에 있다', () {
      final parts = syllableParts('가');
      expect(parts.length, 2);
      for (final p in parts) {
        expect(p.unit.left, greaterThanOrEqualTo(0));
        expect(p.unit.right, lessThanOrEqualTo(1));
        expect(p.unit.top, greaterThanOrEqualTo(0));
        expect(p.unit.bottom, lessThanOrEqualTo(1));
      }
    });

    test('자모 하나는 부분이 없다', () {
      expect(syllableParts('ㄱ'), isEmpty);
    });
  });
}

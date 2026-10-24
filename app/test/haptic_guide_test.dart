import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/services/haptic_guide_rules.dart';

void main() {
  group('거리 → 진동 패턴', () {
    test('보조선 위는 이어지고, 가까우면 촘촘, 멀면 띄엄띄엄', () {
      expect(pulseForDistance(0.0), const GuidePulse(120, 0));
      expect(pulseForDistance(0.039), const GuidePulse(120, 0));
      expect(pulseForDistance(0.04), const GuidePulse(60, 140));
      expect(pulseForDistance(0.12), const GuidePulse(60, 140));
      expect(pulseForDistance(0.121), const GuidePulse(40, 600));
      expect(pulseForDistance(5), const GuidePulse(40, 600));
    });

    test('이어지는 진동은 끝나기 전에, 쉬는 진동은 쉬는 시간이 지난 뒤에 다시 부른다', () {
      expect(const GuidePulse(120, 0).repeatAfterMs, 90);
      expect(const GuidePulse(60, 140).repeatAfterMs, 200);
      expect(const GuidePulse(40, 600).repeatAfterMs, 640);
    });
  });

  group('다시 부를 때 판단', () {
    const near = GuidePulse(60, 140);
    const far = GuidePulse(40, 600);

    test('처음(펜을 댄 순간)에는 바로 부른다', () {
      expect(shouldRepulse(nowMs: 1000, lastMs: null, last: null, next: near), isTrue);
    });

    test('지난 패턴이 끝나기 전에는 다시 부르지 않는다 (부르면 진동이 끊긴다)', () {
      expect(shouldRepulse(nowMs: 1100, lastMs: 1000, last: near, next: near), isFalse);
      expect(shouldRepulse(nowMs: 1199, lastMs: 1000, last: near, next: near), isFalse);
      expect(shouldRepulse(nowMs: 1200, lastMs: 1000, last: near, next: near), isTrue);
    });

    test('거리 구간이 바뀌어도 지난 패턴이 끝날 때까지 기다린다', () {
      expect(shouldRepulse(nowMs: 1300, lastMs: 1000, last: far, next: near), isFalse);
      expect(shouldRepulse(nowMs: 1640, lastMs: 1000, last: far, next: near), isTrue);
    });
  });
}

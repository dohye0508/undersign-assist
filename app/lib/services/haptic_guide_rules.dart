/// 받아쓰기 거리 진동의 패턴 고르기와 다시 부를 때 판단. 순수 함수만 있어서 `flutter test`로 시험된다
/// (`haptic_guide.dart`는 `package:web`을 쓰는 `Haptics`를 부르므로 VM 시험에서 컴파일되지 않는다).
library;

/// 거리 안내 진동 한 주기: [on]ms 울리고 [off]ms 쉰다
class GuidePulse {
  const GuidePulse(this.on, this.off);

  final int on;
  final int off;

  /// 다음 진동을 다시 부를 수 있는 간격. 쉬는 시간이 없는 "이어지는" 진동은 끝나기 조금 전에 다시 불러 끊김이 없게 한다
  int get repeatAfterMs => off == 0 ? on - 30 : on + off;

  @override
  bool operator ==(Object other) => other is GuidePulse && other.on == on && other.off == off;

  @override
  int get hashCode => Object.hash(on, off);

  @override
  String toString() => 'GuidePulse($on, $off)';
}

/// 보조 글자 크기 대비 거리(0 = 글자 위)로 진동 패턴을 고른다
GuidePulse pulseForDistance(double fraction) {
  if (fraction < 0.04) return const GuidePulse(120, 0); // 보조선 위: 이어지는 진동
  if (fraction <= 0.12) return const GuidePulse(60, 140); // 가까움: 촘촘하게
  return const GuidePulse(40, 600); // 멂: 띄엄띄엄
}

/// 지금 다시 진동을 불러야 하는지. [lastMs]가 null이면 아직 한 번도 안 불렀으니 바로 부른다.
/// 거리 구간이 바뀌어 패턴이 달라졌어도([last] != [next]) 지난 패턴이 끝날 때까지 기다린다 (부르면 끊기므로)
bool shouldRepulse({required int nowMs, required int? lastMs, required GuidePulse? last, required GuidePulse next}) {
  if (lastMs == null || last == null) return true;
  return nowMs - lastMs >= last.repeatAfterMs;
}

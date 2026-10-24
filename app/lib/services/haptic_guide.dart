import '../features/practice/score_store.dart';
import 'haptic_guide_rules.dart';
import 'haptics.dart';

export 'haptic_guide_rules.dart';

/// 쓰는 동안의 연속 진동 안내 (받아쓰기). 기존 [Haptics]는 한 번 울리는 신호이고, 이건 계속 이어지는 안내다.
///
/// 웹 진동(`navigator.vibrate`)의 두 제약을 함께 피한다:
/// 1. 부를 때마다 진행 중인 패턴을 끊는다 → 펜이 움직일 때마다 부르지 않고, 지난 패턴이 끝났을 때만 다시 부른다.
/// 2. 크롬은 사용자 제스처(펜·손가락이 눌린 동안의 pointer 이벤트) 안에서 부른 것만 허락하고, 타이머 콜백에서
///    부르면 "Blocked call to navigator.vibrate" 경고와 함께 false를 돌려준다 → 타이머를 쓰지 않고
///    **pointermove 이벤트 안에서** 부른다. 펜이 멈추면 진동도 패턴 끝에서 멈추는데, 그건 의도한 바다
///    (멈춘 펜에는 안내할 거리 변화가 없다).
class HapticGuide {
  HapticGuide(this.settings);

  final PracticeSettings settings;

  bool _active = false;
  int? _lastPulseMs;
  GuidePulse? _lastPulse;
  int _lastOffLineMs = 0;
  int _lastOutsideMs = 0;

  bool get running => _active;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 거리 안내를 시작한다 (학습하기: 펜을 대는 순간). pointerdown 안이므로 첫 진동을 바로 울린다
  void start(double distanceFraction) {
    _active = true;
    _lastPulseMs = null;
    _lastPulse = null;
    _feel(distanceFraction);
  }

  /// 펜이 움직였다 (pointermove 안에서 부른다). [fraction]은 보조 글자 크기 대비 거리 (0 = 글자 위)
  void update(double fraction) {
    if (!_active) {
      start(fraction);
      return;
    }
    _feel(fraction);
  }

  /// 펜을 뗐다
  void stop() {
    if (!_active) return;
    _active = false;
    _lastPulseMs = null;
    _lastPulse = null;
    if (settings.vibrate) Haptics.cancel();
  }

  void _feel(double fraction) {
    final next = pulseForDistance(fraction);
    final now = _now();
    if (!shouldRepulse(nowMs: now, lastMs: _lastPulseMs, last: _lastPulse, next: next)) return;
    _lastPulseMs = now;
    _lastPulse = next;
    if (settings.vibrate) Haptics.pulse([next.on]);
    if (settings.distanceSound) {
      // 가까울수록 높은 음
      final closeness = (1 - (fraction / 0.2)).clamp(0.0, 1.0).toDouble();
      Haptics.tone(330 + 550 * closeness, length: next.on / 1000 * 0.8);
    }
  }

  /// 연습하기: 펜이 보조선 줄의 위아래 띠를 벗어났다. 짧게 두 번 톡톡 (0.5초에 한 번까지)
  void offLine() {
    final now = _now();
    if (now - _lastOffLineMs < 500) return;
    _lastOffLineMs = now;
    if (settings.vibrate) Haptics.pulse([30, 60, 30]);
    if (settings.distanceSound) Haptics.tone(520, length: 0.04);
  }

  /// 펜이 쓰기 칸 밖으로 나갔다. 길게 한 번 + 낮은음 (1초에 한 번까지)
  void outside() {
    final now = _now();
    if (now - _lastOutsideMs < 1000) return;
    _lastOutsideMs = now;
    if (settings.vibrate) Haptics.pulse([250]);
    Haptics.tone(220, length: 0.25, gain: 0.15);
  }

  void dispose() => stop();
}

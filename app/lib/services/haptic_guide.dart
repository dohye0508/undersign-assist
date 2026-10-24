import 'dart:async';

import '../features/practice/score_store.dart';
import 'haptics.dart';

/// 쓰는 동안의 연속 진동 안내 (받아쓰기). 기존 [Haptics]는 한 번 울리는 신호이고, 이건 계속 이어지는 안내다.
///
/// 웹 진동(`navigator.vibrate`)은 세기를 못 바꾸고, 부를 때마다 진행 중인 패턴을 끊는다.
/// 그래서 펜이 움직일 때마다 부르지 않는다. 펜이 움직일 때는 최근 거리만 저장해 두고,
/// 타이머가 한 주기가 시작될 때마다 그 거리로 다음 진동을 고른다.
class HapticGuide {
  HapticGuide(this.settings);

  final PracticeSettings settings;

  Timer? _timer;
  double? _distance;
  DateTime _lastOffLine = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOutside = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _timer != null;

  /// 거리 안내를 시작한다 (학습하기: 펜을 대는 순간)
  void start(double distanceFraction) {
    _distance = distanceFraction;
    if (_timer == null) _tick();
  }

  /// 펜이 움직였다. [fraction]은 보조 글자 크기 대비 거리 (0 = 글자 위)
  void update(double fraction) {
    _distance = fraction;
    if (_timer == null) _tick();
  }

  /// 펜을 뗐다
  void stop() {
    _timer?.cancel();
    _timer = null;
    _distance = null;
    if (settings.vibrate) Haptics.cancel();
  }

  void _tick() {
    final d = _distance;
    if (d == null) {
      _timer = null;
      return;
    }
    final int on;
    final int off;
    if (d < 0.04) {
      on = 120; // 보조선 위: 이어지는 진동
      off = 0;
    } else if (d <= 0.12) {
      on = 60; // 가까움: 촘촘하게
      off = 140;
    } else {
      on = 40; // 멂: 띄엄띄엄
      off = 600;
    }
    if (settings.vibrate) Haptics.pulse([on]);
    if (settings.distanceSound) {
      // 가까울수록 높은 음
      final closeness = (1 - (d / 0.2)).clamp(0.0, 1.0).toDouble();
      Haptics.tone(330 + 550 * closeness, length: on / 1000 * 0.8);
    }
    _timer = Timer(Duration(milliseconds: on + off), _tick);
  }

  /// 연습하기: 펜이 보조선 줄의 위아래 띠를 벗어났다. 짧게 두 번 톡톡 (0.5초에 한 번까지)
  void offLine() {
    final now = DateTime.now();
    if (now.difference(_lastOffLine).inMilliseconds < 500) return;
    _lastOffLine = now;
    if (settings.vibrate) Haptics.pulse([30, 60, 30]);
    if (settings.distanceSound) Haptics.tone(520, length: 0.04);
  }

  /// 펜이 쓰기 칸 밖으로 나갔다. 길게 한 번 + 낮은음 (1초에 한 번까지)
  void outside() {
    final now = DateTime.now();
    if (now.difference(_lastOutside).inMilliseconds < 1000) return;
    _lastOutside = now;
    if (settings.vibrate) Haptics.pulse([250]);
    Haptics.tone(220, length: 0.25, gain: 0.15);
  }

  void dispose() => stop();
}

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 진동과 짧은 소리 신호. 진동 주체는 패드(기기)다 (계획서 확정).
///
/// 브라우저 진동(navigator.vibrate)은 안드로이드 크롬에서만 동작하고 노트북·아이패드에서는 무시된다.
/// 쓸 기기가 아직 정해지지 않아서 소리를 항상 함께 낸다.
class Haptics {
  Haptics._();

  static web.AudioContext? _audio;

  /// 잘못됨: 강하게 두 번 + 낮은음 두 번 (이전 앱의 진동 'w'와 같은 뜻)
  static void warn() {
    _vibrate([200, 100, 200]);
    _tones([330, 330]);
  }

  /// 잘됨: 짧게 한 번 + 높은음 한 번 (이전 앱의 진동 's'와 같은 뜻)
  static void ok() {
    _vibrate([120]);
    _tones([880]);
  }

  static void _vibrate(List<int> pattern) {
    try {
      web.window.navigator.vibrate(pattern.jsify()!);
    } catch (_) {
      // 진동을 지원하지 않는 기기
    }
  }

  static void _tones(List<double> frequencies) {
    try {
      final audio = _audio ??= web.AudioContext();
      for (final (i, frequency) in frequencies.indexed) {
        final oscillator = audio.createOscillator()..frequency.value = frequency;
        oscillator.connect(audio.destination);
        final start = audio.currentTime + i * 0.28;
        oscillator.start(start);
        oscillator.stop(start + 0.16);
      }
    } catch (_) {
      // 소리를 낼 수 없는 환경
    }
  }
}

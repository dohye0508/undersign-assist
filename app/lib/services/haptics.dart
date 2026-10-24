import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 진동과 짧은 소리 신호. 진동 주체는 패드(기기)다 (계획서 확정).
///
/// 브라우저 진동(navigator.vibrate)은 안드로이드 크롬에서만 동작하고 노트북·아이패드에서는 무시된다.
/// 쓸 기기가 아직 정해지지 않아서 소리를 항상 함께 낸다.
class Haptics {
  Haptics._();

  static web.AudioContext? _audio;

  /// 진동 켜기/끄기 (설정 화면). 끄면 버튼 진동과 받아쓰기 안내 진동이 모두 꺼진다
  static bool vibrationEnabled = true;

  /// 효과음 크기 배율 (설정 화면: 끄기 0 / 작게 0.5 / 보통 1 / 크게 1.6). 모든 소리 신호의 gain에 곱한다
  static double effectVolume = 1.0;

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

  /// 버튼을 눌렀을 때: 아주 짧은 진동 + 작은 딸깍 소리. 모든 버튼이 이걸 낸다 (시각장애인은 눌렸는지 이걸로 안다)
  static void tap() {
    _vibrate([30]);
    _tones([1200], length: 0.05, gain: 0.1);
  }

  /// 쓴 것을 왼쪽으로 밀어 넘겼을 때: 약한 진동 + 중간음
  static void slide() {
    _vibrate([50]);
    _tones([660], length: 0.1, gain: 0.18);
  }

  /// 받아쓰기의 연속 안내용: 진동만 / 소리만 따로 낸다 (경고·성공처럼 둘을 묶어 내지 않는다)
  static void pulse(List<int> pattern) => _vibrate(pattern);

  /// 진행 중인 진동을 멈춘다
  static void cancel() => _vibrate([0]);

  static void tone(double frequency, {double length = 0.05, double gain = 0.1}) =>
      _tones([frequency], length: length, gain: gain);

  static void _vibrate(List<int> pattern) {
    // 끄기(0)는 꺼진 상태에서도 보내서 이어지던 진동을 멈춘다
    if (!vibrationEnabled && !(pattern.length == 1 && pattern.first == 0)) return;
    try {
      web.window.navigator.vibrate(pattern.jsify()!);
    } catch (_) {
      // 진동을 지원하지 않는 기기
    }
  }

  // 효과음이 음성(TTS)보다 크게 들린다는 피드백으로 기본 크기를 0.3으로 낮췄다 (2026-10-24)
  static void _tones(List<double> frequencies, {double length = 0.16, double gain = 0.3}) {
    if (effectVolume <= 0) return;
    gain *= effectVolume;
    try {
      final audio = _audio ??= web.AudioContext();
      for (final (i, frequency) in frequencies.indexed) {
        final oscillator = audio.createOscillator()..frequency.value = frequency;
        final volume = audio.createGain()..gain.value = gain;
        oscillator.connect(volume);
        volume.connect(audio.destination);
        final start = audio.currentTime + i * 0.28;
        oscillator.start(start);
        oscillator.stop(start + length);
      }
    } catch (_) {
      // 소리를 낼 수 없는 환경
    }
  }
}

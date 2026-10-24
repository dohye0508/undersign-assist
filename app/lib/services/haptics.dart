import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// 마지막 `navigator.vibrate` 호출이 어떻게 됐는지 (패드에서 진동이 안 날 때 원인을 바로 보기 위한 디버그 정보)
enum VibrateStatus {
  /// 아직 한 번도 부르지 않았다
  unknown,

  /// 브라우저에 `navigator.vibrate`가 없다 (iOS Safari, 일부 데스크톱)
  unsupported,

  /// 브라우저가 false를 돌려줬다. 크롬은 사용자 제스처(터치) 밖에서 부르면 막는다
  blocked,

  /// true를 돌려줬다 (데스크톱 크롬은 true를 주고도 모터가 없어 아무 느낌이 없다)
  ok;

  String get label => switch (this) {
        VibrateStatus.unknown => '아직 안 함',
        VibrateStatus.unsupported => '지원 안 함',
        VibrateStatus.blocked => '차단됨',
        VibrateStatus.ok => '됨',
      };
}

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

  /// 마지막으로 진동을 울리려 했을 때의 결과 (멈추기용 `vibrate(0)`은 세지 않는다)
  static VibrateStatus lastVibrateResult = VibrateStatus.unknown;

  /// `navigator.vibrate`가 있는 브라우저인지. 없으면 null (아직 모름)이 아니라 false
  static bool get vibrateSupported {
    try {
      return (web.window.navigator as JSObject).has('vibrate');
    } catch (_) {
      return false;
    }
  }

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

  /// 받아쓰기의 연속 안내용: 진동만 / 소리만 따로 낸다 (경고·성공처럼 둘을 묶어 내지 않는다).
  /// 돌려주는 값은 브라우저가 진동을 받아들였는지(`navigator.vibrate`의 반환값). 꺼져 있거나 못 울리면 false
  static bool pulse(List<int> pattern) => _vibrate(pattern);

  /// 진행 중인 진동을 멈춘다
  static void cancel() => _vibrate([0]);

  static void tone(double frequency, {double length = 0.05, double gain = 0.1}) =>
      _tones([frequency], length: length, gain: gain);

  /// `navigator.vibrate`를 부른다. 패턴은 `List<int>`를 그대로 넘기지 않고 JS 숫자 배열(`JSArray<JSNumber>`)로 바꿔 넘긴다.
  /// 크롬은 사용자가 화면을 누르고 있는 동안(또는 그 직후)에만 진동을 허락하고, 그 밖(타이머 콜백 등)에서 부르면
  /// 조용히 false를 돌려준다. 그 값을 [lastVibrateResult]에 남겨 화면에서 볼 수 있게 한다
  static bool _vibrate(List<int> pattern) {
    final isCancel = pattern.length == 1 && pattern.first == 0;
    // 끄기(0)는 꺼진 상태에서도 보내서 이어지던 진동을 멈춘다
    if (!vibrationEnabled && !isCancel) return false;
    try {
      final navigator = web.window.navigator;
      if (!(navigator as JSObject).has('vibrate')) {
        if (!isCancel) lastVibrateResult = VibrateStatus.unsupported;
        return false;
      }
      final jsPattern = pattern.map((ms) => ms.toJS).toList().toJS;
      final accepted = navigator.vibrate(jsPattern);
      if (!isCancel) lastVibrateResult = accepted ? VibrateStatus.ok : VibrateStatus.blocked;
      return accepted;
    } catch (_) {
      // 진동을 지원하지 않는 기기
      if (!isCancel) lastVibrateResult = VibrateStatus.unsupported;
      return false;
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

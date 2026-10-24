import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 결과는 음성(TTS)과 스크린리더 알림으로 함께 전한다. 사용자는 화면을 볼 수 없다고 가정한다.
class Speech {
  Speech._();

  /// 말하는 속도. flutter_tts 웹은 0~1이고 0.5가 보통 속도라 0.65 ≈ 1.3배.
  /// 처음 값이고, 설정 화면(말하기 속도)에서 바꾸면 [setRate]로 바뀐다
  static double _rate = 0.65;
  static double get speechRate => _rate;

  /// 말소리 크기 (0~1). 설정 화면(말소리 크기)에서 바꾼다
  static double _volume = 1.0;
  static double get volume => _volume;

  static final _tts = FlutterTts()
    ..setLanguage('ko-KR')
    ..setSpeechRate(_rate)
    ..setVolume(_volume);

  /// 마지막으로 말한 문장 ("다시 듣기"용)
  static final lastMessage = ValueNotifier<String>('');

  static Future<void> setRate(double rate) async {
    _rate = rate;
    await _tts.setSpeechRate(rate);
  }

  static Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await _tts.setVolume(_volume);
  }

  static Future<void> announce(BuildContext context, String text) async {
    lastMessage.value = text;
    // ignore: deprecated_member_use
    SemanticsService.announce(text, Directionality.of(context));
    await _tts.stop();
    await _tts.speak(text);
  }

  static Future<void> stop() => _tts.stop();
}

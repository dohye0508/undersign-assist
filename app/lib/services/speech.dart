import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 결과는 음성(TTS)과 스크린리더 알림으로 함께 전한다. 사용자는 화면을 볼 수 없다고 가정한다.
/// 마지막으로 말한 문장은 화면의 "음성 안내" 칸에도 보인다 (곁에서 돕는 사람과 시연용).
class Speech {
  Speech._();

  static final _tts = FlutterTts()..setLanguage('ko-KR');

  static final lastMessage = ValueNotifier<String>('');

  static Future<void> announce(BuildContext context, String text) async {
    lastMessage.value = text;
    // ignore: deprecated_member_use
    SemanticsService.announce(text, Directionality.of(context));
    await _tts.stop();
    await _tts.speak(text);
  }

  static Future<void> stop() => _tts.stop();
}

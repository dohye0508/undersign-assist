import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 결과는 음성(TTS)과 스크린리더 알림으로 함께 전한다. 사용자는 화면을 볼 수 없다고 가정한다.
class Speech {
  Speech._();

  static final _tts = FlutterTts()..setLanguage('ko-KR');

  /// 마지막으로 말한 문장 ("다시 듣기"용)
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

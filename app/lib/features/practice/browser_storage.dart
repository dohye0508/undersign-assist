import 'package:web/web.dart' as web;

import 'score_store.dart';

/// 브라우저 localStorage. 막혀 있거나 실패해도 앱이 멈추지 않게 감싼다 (비공개 창 등).
/// 웹 전용 코드라서 [ScoreStore]와 따로 두었다 (그래야 ScoreStore를 `flutter test`로 시험할 수 있다)
class BrowserStorage implements KeyValueStorage {
  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // 저장할 수 없는 환경: 이번 실행 동안만 기억한다
    }
  }
}

/// 앱 전체가 같이 쓰는 저장소 (이 기기의 브라우저)
final ScoreStore sharedScoreStore = ScoreStore(BrowserStorage());

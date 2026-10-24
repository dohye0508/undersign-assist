import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../practice/score_store.dart' show KeyValueStorage;

/// 단계로 고르는 설정 값 하나 (말하기 속도 "빠르게" 같은 것)
class SettingLevel {
  const SettingLevel(this.id, this.label, this.value);

  /// 저장할 때 쓰는 이름. 값(숫자)을 나중에 바꿔도 저장값이 깨지지 않게 이름으로 저장한다
  final String id;

  /// 화면과 음성에 쓰는 이름
  final String label;
  final double value;
}

/// 말하기 속도. flutter_tts 웹은 0~1이고 0.5가 보통 속도다. 처음 값은 빠르게(0.65 ≈ 1.3배)
const speechRates = [
  SettingLevel('slow', '느리게', 0.4),
  SettingLevel('normal', '보통', 0.5),
  SettingLevel('fast', '빠르게', 0.65),
  SettingLevel('faster', '아주 빠르게', 0.8),
];

/// 말소리 크기 (TTS volume, 0~1). 처음 값은 크게(1.0, 예전과 같음)
const speechVolumes = [
  SettingLevel('small', '작게', 0.5),
  SettingLevel('normal', '보통', 0.75),
  SettingLevel('large', '크게', 1.0),
];

/// 효과음 크기 (딸깍·맞음·틀림 소리 gain에 곱하는 배율). 처음 값은 보통(1.0)
const effectVolumes = [
  SettingLevel('off', '끄기', 0),
  SettingLevel('small', '작게', 0.5),
  SettingLevel('normal', '보통', 1.0),
  SettingLevel('large', '크게', 1.6),
];

/// 앱 전체 설정: 말하기 속도, 말소리 크기, 효과음 크기, 진동.
/// 이 기기 브라우저 저장소에 저장해 앱을 다시 켜도 남는다.
/// 웹 코드(Speech, Haptics)를 부르지 않아서 `flutter test`로 시험할 수 있다. 적용은 `device_settings.dart`가 한다
class AppSettings extends ChangeNotifier {
  AppSettings(this._storage) {
    _load();
  }

  static const storageKey = 'undersign.settings.v1';

  final KeyValueStorage _storage;

  SettingLevel speechRate = speechRates[2];
  SettingLevel speechVolume = speechVolumes[2];
  SettingLevel effectVolume = effectVolumes[2];

  /// 진동 (안드로이드 크롬에서만 난다). 끄면 버튼 진동과 받아쓰기 안내 진동이 모두 꺼진다
  bool vibrate = true;

  void _load() {
    final raw = _storage.read(storageKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      speechRate = _pick(speechRates, json['speechRate'], speechRate);
      speechVolume = _pick(speechVolumes, json['speechVolume'], speechVolume);
      effectVolume = _pick(effectVolumes, json['effectVolume'], effectVolume);
      if (json['vibrate'] is bool) vibrate = json['vibrate'] as bool;
    } catch (_) {
      // 깨진 저장값은 버리고 처음 값으로
    }
  }

  static SettingLevel _pick(List<SettingLevel> levels, Object? id, SettingLevel fallback) {
    for (final level in levels) {
      if (level.id == id) return level;
    }
    return fallback;
  }

  void update(void Function(AppSettings) change) {
    change(this);
    _storage.write(
      storageKey,
      jsonEncode({
        'speechRate': speechRate.id,
        'speechVolume': speechVolume.id,
        'effectVolume': effectVolume.id,
        'vibrate': vibrate,
      }),
    );
    notifyListeners();
  }

  /// 설정 화면을 열 때 읽어 주는 지금 값
  String summarySpeech() =>
      '지금 말하기 속도는 ${speechRate.label}, 말소리 크기는 ${speechVolume.label}, '
      '효과음은 ${effectVolume.label}, 진동은 ${vibrate ? '켜짐' : '꺼짐'}이에요.';
}

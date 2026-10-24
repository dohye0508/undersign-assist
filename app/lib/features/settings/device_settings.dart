import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../practice/browser_storage.dart';
import 'app_settings.dart';

/// 이 기기 브라우저에 저장된 앱 설정 (앱 전체가 같이 쓴다)
final AppSettings sharedAppSettings = AppSettings(BrowserStorage());

/// 설정 값을 음성(Speech)과 진동·소리(Haptics)에 적용한다. 앱 시작 때와 값을 바꿀 때마다 부른다
Future<void> applyAppSettings([AppSettings? settings]) async {
  final s = settings ?? sharedAppSettings;
  // 진동을 끄는 순간 이어지던 진동도 멈춘다
  if (!s.vibrate) Haptics.cancel();
  Haptics.vibrationEnabled = s.vibrate;
  Haptics.effectVolume = s.effectVolume.value;
  await Speech.setRate(s.speechRate.value);
  await Speech.setVolume(s.speechVolume.value);
}

/// 값을 바꾸고 저장한 뒤 바로 적용한다
Future<void> updateAppSettings(void Function(AppSettings) change) async {
  sharedAppSettings.update(change);
  await applyAppSettings();
}

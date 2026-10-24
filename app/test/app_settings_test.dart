import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/score_store.dart';
import 'package:undersign_assist/features/settings/app_settings.dart';

void main() {
  test('처음 값: 말하기 빠르게(0.65), 말소리 크게, 효과음 보통, 진동 켬', () {
    final s = AppSettings(MemoryStorage());
    expect(s.speechRate.value, 0.65);
    expect(s.speechVolume.label, '크게');
    expect(s.effectVolume.value, 1.0);
    expect(s.vibrate, isTrue);
  });

  test('바꾼 값은 다시 열어도 남는다', () {
    final storage = MemoryStorage();
    AppSettings(storage).update((s) {
      s.speechRate = speechRates.first;
      s.effectVolume = effectVolumes.first;
      s.vibrate = false;
    });
    final again = AppSettings(storage);
    expect(again.speechRate.label, '느리게');
    expect(again.effectVolume.value, 0);
    expect(again.vibrate, isFalse);
  });

  test('깨진 저장값이나 모르는 단계는 처음 값으로', () {
    final broken = MemoryStorage()..write(AppSettings.storageKey, '{깨짐');
    expect(AppSettings(broken).speechRate.id, 'fast');
    final unknown = MemoryStorage()..write(AppSettings.storageKey, '{"speechRate":"warp","vibrate":"yes"}');
    final s = AppSettings(unknown);
    expect(s.speechRate.id, 'fast');
    expect(s.vibrate, isTrue);
  });
}

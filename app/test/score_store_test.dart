import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/practice_items.dart';
import 'package:undersign_assist/features/practice/score_store.dart';

void main() {
  const giyeok = PracticeItem(PracticeKind.consonant, 'ㄱ');
  const nieun = PracticeItem(PracticeKind.consonant, 'ㄴ');
  const ga = PracticeItem(PracticeKind.syllable, '가');

  test('점수는 최근 10개만 남는다', () {
    final store = ScoreStore(MemoryStorage());
    for (var i = 0; i < 15; i++) {
      store.record(giyeok, i * 5);
    }
    expect(store.recent(giyeok.key).length, ScoreStore.maxRecent);
    expect(store.recent(giyeok.key).last, 70);
  });

  test('종류별 평균', () {
    final store = ScoreStore(MemoryStorage());
    expect(store.average(PracticeKind.consonant), isNull);
    store.record(giyeok, 80);
    store.record(nieun, 60);
    expect(store.average(PracticeKind.consonant), 70);
    expect(store.average(PracticeKind.vowel), isNull);
  });

  test('이름과 점수와 설정은 다시 열어도 남는다', () {
    final storage = MemoryStorage();
    final first = ScoreStore(storage)
      ..setName('김이름')
      ..record(ga, 88)
      ..updateSettings((s) => s.hideGuide = true);

    final second = ScoreStore(storage);
    expect(second.name, '김이름');
    expect(second.recent(ga.key), [88]);
    expect(second.settings.hideGuide, isTrue);
    expect(second.settings.vibrate, isTrue);
    expect(first.name, second.name);
  });

  test('깨진 저장값은 버리고 처음부터', () {
    final storage = MemoryStorage()..write('undersign.practice.v1', '{깨짐');
    final store = ScoreStore(storage);
    expect(store.name, '');
  });

  test('점수판 말: 점수가 없을 때', () {
    expect(ScoreStore(MemoryStorage()).boardSpeech(), contains('아직 점수가 없어요'));
  });

  test('점수판 말: 가장 낮은 글자는 자음이면 이름으로 부른다', () {
    final store = ScoreStore(MemoryStorage())
      ..record(giyeok, 90)
      ..record(nieun, 40);
    expect(store.lowestItemName(), '니은');
    expect(store.boardSpeech(), contains('니은이에요'));
  });

  test('가장 많이 오른 종류', () {
    final store = ScoreStore(MemoryStorage())
      ..record(giyeok, 40)
      ..record(giyeok, 80)
      ..record(ga, 70)
      ..record(ga, 60);
    expect(store.mostImproved(), PracticeKind.consonant);
  });
}

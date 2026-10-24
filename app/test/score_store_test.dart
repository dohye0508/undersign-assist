import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/practice_items.dart';
import 'package:undersign_assist/features/practice/profile_format.dart';
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

  test('내 정보는 저장되고 다시 열어도 남는다. 비우면 지워진다', () {
    final storage = MemoryStorage();
    ScoreStore(storage).setProfile(name: '김이름', address: ' 서울시 강남구 테헤란로 12 ', birth: '2008년 3월 15일', phone: '010-1234-5678');

    final second = ScoreStore(storage);
    expect(second.name, '김이름');
    expect(second.address, '서울시 강남구 테헤란로 12');
    expect(second.birth, '2008년 3월 15일');
    expect(second.phone, '010-1234-5678');
    expect(second.hasProfile, isTrue);
    expect(second.profileLabels, ['이름', '주소', '생년월일', '전화번호']);

    second.setProfile(address: '', phone: '');
    final third = ScoreStore(storage);
    expect(third.address, '');
    expect(third.phone, '');
    expect(third.name, '김이름', reason: '넘기지 않은 값은 그대로');
    expect(third.profileLabels, ['이름', '생년월일']);
  });

  test('생년월일 정규화: 숫자만 들어와도 "2008년 3월 15일" 꼴', () {
    expect(normalizeBirth('20080315'), '2008년 3월 15일');
    expect(normalizeBirth('2008-03-15'), '2008년 3월 15일');
    expect(normalizeBirth('2008.3.15'), '2008년 3월 15일');
    expect(normalizeBirth('2008/3/15'), '2008년 3월 15일');
    expect(normalizeBirth(' 2008년 03월 15일 '), '2008년 3월 15일');
    expect(normalizeBirth(''), '');
    expect(normalizeBirth('20081340'), '20081340', reason: '13월은 날짜가 아니라 그대로 둔다');
    expect(normalizeBirth('삼월'), '삼월');
    expect(splitBirth('2008년 3월 15일'), ['2008', '3', '15']);
    expect(splitBirth('모름'), isEmpty);
  });

  test('전화번호와 주소 나누기', () {
    expect(normalizePhone('010 1234 5678'), '010-1234-5678');
    expect(normalizePhone('01012345678'), '010-1234-5678');
    expect(normalizePhone('0212345678'), '021-234-5678');
    expect(normalizePhone('010--1234-'), '010-1234');
    expect(splitPhone('010-1234-5678'), ['010', '1234', '5678']);
    expect(splitAddress('  서울시  강남구 테헤란로 12 '), ['서울시', '강남구', '테헤란로', '12']);
  });

  test('내 정보 낱말: 등록된 것만, 긴 것은 나눠서, 무엇인지 먼저 말한다', () {
    final items = wordItems(
      WordGroup.myInfo,
      profile: const ProfileInfo(name: '김이름', address: '서울시 강남구', birth: '2008년 3월 15일', phone: '010-1234-5678'),
    );
    expect(items.map((i) => i.text).toList(), ['김이름', '서울시', '강남구', '2008', '3', '15', '010', '1234', '5678']);
    expect(items.first.speech, startsWith('이름, 김이름'));
    expect(items[2].speech, startsWith('주소의 2번째 낱말, 강남구'));
    expect(items[3].speech, startsWith('생년월일의 연도, 2008'));
    expect(items[6].speech, startsWith('전화번호의 1번째 덩어리, 010'));
    expect(wordItems(WordGroup.myInfo), isEmpty);
    expect(wordItems(WordGroup.myInfo, profile: const ProfileInfo(name: '김이름')).length, 1);
  });

  test('날짜 낱말: 오늘의 연·월·일, 생년월일이 있으면 그것도', () {
    final today = DateTime(2026, 10, 25);
    final items = wordItems(WordGroup.date, today: today);
    expect(items.map((i) => i.text).toList(), ['2026', '10', '25']);
    expect(items.first.speech, startsWith('오늘 날짜의 연도, 2026'));
    final withBirth = wordItems(WordGroup.date, today: today, profile: const ProfileInfo(birth: '2008년 3월 15일'));
    expect(withBirth.map((i) => i.text).toList(), ['2026', '10', '25', '2008', '3', '15']);
    expect(withBirth[3].speech, startsWith('생년월일의 연도, 2008'));
  });

  test('계약서 낱말에 주소·생년월일·전화번호·연락처가 있다', () {
    expect(contractWords, containsAll(['주소', '생년월일', '전화번호', '연락처']));
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

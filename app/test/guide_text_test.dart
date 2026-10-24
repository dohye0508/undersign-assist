import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/guide_text.dart';
import 'package:undersign_assist/features/practice/score_store.dart';
import 'package:undersign_assist/models/fill.dart';
import 'package:undersign_assist/models/recognized_document.dart';

FillTarget _text(String label, {String id = 'p0-l1-x'}) =>
    FillTarget(id: id, label: label, page: 0, rect: const Box(0, 0, 100, 20), isSignature: false);

FillTarget _date(String part, {String label = '날짜'}) =>
    FillTarget(id: 'p0-l9-c3-날짜-$part', label: '$label $part', page: 0, rect: const Box(0, 0, 100, 20), isSignature: false);

ScoreStore _store({String name = '김이름', String address = '서울시 어느 구', String birth = '2008년 3월 15일', String phone = ''}) {
  return ScoreStore(MemoryStorage())
    ..name = name
    ..address = address
    ..birth = birth
    ..phone = phone;
}

void main() {
  final today = DateTime(2026, 10, 25);

  test('본인 성명 칸에는 등록한 이름', () {
    expect(guideTextFor(_text('학생 성명'), _store()), '김이름');
    expect(guideTextFor(_text('성명'), _store()), '김이름');
    expect(guideTextFor(_text('근로자 성명'), _store()), '김이름');
    expect(guideTextFor(_text('지원자 이름'), _store()), '김이름');
    expect(guideTextFor(_text('2페이지 둘째 성명'), _store()), '김이름');
  });

  test('본인이 아닌 주체의 칸에는 깔지 않는다', () {
    expect(guideTextFor(_text('보호자 성명'), _store()), isNull);
    expect(guideTextFor(_text('학부모 성명'), _store()), isNull);
    expect(guideTextFor(_text('법정대리인 성명'), _store()), isNull);
    expect(guideTextFor(_text('사업주 주소'), _store()), isNull);
    expect(guideTextFor(_text('대표자 성명'), _store()), isNull);
    expect(guideTextFor(_text('갑 성명'), _store()), isNull);
  });

  test('주소·생년월일·연락처', () {
    expect(guideTextFor(_text('주소'), _store()), '서울시 어느 구');
    expect(guideTextFor(_text('근로자 주소'), _store()), '서울시 어느 구');
    expect(guideTextFor(_text('생년월일'), _store()), '2008년 3월 15일');
    expect(guideTextFor(_text('연락처'), _store(phone: '010-1234-5678')), '010-1234-5678');
    expect(guideTextFor(_text('전화번호'), _store(phone: '010-1234-5678')), '010-1234-5678');
  });

  test('날짜 칸은 오늘 날짜의 그 부분', () {
    expect(guideTextFor(_date('연도'), _store(), now: today), '2026');
    expect(guideTextFor(_date('월'), _store(), now: today), '10');
    expect(guideTextFor(_date('일'), _store(), now: today), '25');
    // 등록 값이 없어도 날짜는 깔린다
    expect(guideTextFor(_date('연도'), _store(name: '', address: '', birth: ''), now: today), '2026');
  });

  test('생년월일 날짜 칸은 등록한 생년월일에서', () {
    expect(guideTextFor(_date('연도', label: '생년월일'), _store(), now: today), '2008');
    expect(guideTextFor(_date('월', label: '생년월일'), _store(), now: today), '3');
    expect(guideTextFor(_date('일', label: '생년월일'), _store(), now: today), '15');
    expect(guideTextFor(_date('월', label: '생년월일'), _store(birth: ''), now: today), isNull);
    expect(guideTextFor(_date('월', label: '보호자 생년월일'), _store(), now: today), isNull);
  });

  test('값이 없으면 null', () {
    expect(guideTextFor(_text('성명'), _store(name: '')), isNull);
    expect(guideTextFor(_text('성명'), _store(name: '   ')), isNull);
    expect(guideTextFor(_text('주소'), _store(address: '')), isNull);
    expect(guideTextFor(_text('연락처'), _store()), isNull);
    expect(guideTextFor(_text('접수번호'), _store()), isNull);
  });

  test('서명·체크 칸에는 깔지 않는다', () {
    final sign = FillTarget(id: 'p0-l1-s', label: '학생 서명', page: 0, rect: const Box(0, 0, 10, 10), isSignature: true);
    expect(guideTextFor(sign, _store()), isNull);
    expect(guideTextFor(_text('수집·이용 동의 여부'), _store()), isNull);
  });

  test('음성 안내 문장', () {
    expect(guideFor(_text('성명'), _store())!.spoken, '등록한 이름 김이름이 회색으로 보여요. 따라 써도 돼요.');
    expect(guideFor(_date('연도'), _store(), now: today)!.spoken, '오늘 날짜 2026이 회색으로 보여요. 따라 써도 돼요.');
    expect(guideFor(_date('일'), _store(), now: today)!.spoken, '오늘 날짜 25가 회색으로 보여요. 따라 써도 돼요.');
    expect(guideFor(_text('주소'), _store())!.spoken, '등록한 주소가 회색으로 보여요. 따라 써도 돼요.');
  });

  test('생년월일 글자 읽기', () {
    expect(parseBirth('2008년 3월 15일'), (year: 2008, month: 3, day: 15));
    expect(parseBirth('2008.03.15'), (year: 2008, month: 3, day: 15));
    expect(parseBirth('20080315'), (year: 2008, month: 3, day: 15));
    expect(parseBirth(''), isNull);
    expect(parseBirth('삼월'), isNull);
  });
}

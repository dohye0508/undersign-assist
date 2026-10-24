import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/feedback.dart';
import 'package:undersign_assist/features/practice/stroke_metrics.dart';

/// 40×40칸(칸 하나 4px, 전체 160px) 보조 글자 "ㄱ": 위 가로획과 오른쪽 세로획
GuideMap giyeok() {
  const n = 40;
  final rows = [
    for (var y = 0; y < n; y++)
      [
        for (var x = 0; x < n; x++)
          ((y >= 6 && y <= 11 && x >= 8 && x <= 31) || (x >= 26 && x <= 31 && y >= 6 && y <= 33)) ? '#' : '.',
      ].join(),
  ];
  return GuideMap.fromAscii(rows);
}

PracticeVerdict judge(List<List<Offset>> strokes, {GuideMap? guide}) {
  final map = guide ?? giyeok();
  return PracticeJudge.judge(StrokeMetrics.measure(strokes, map), label: '기역');
}

void main() {
  group('거리 지도', () {
    test('글자 칸에서 멀어질수록 거리가 1씩 는다', () {
      final map = GuideMap.fromAscii([
        '.....',
        '.....',
        '..#..',
        '.....',
        '.....',
      ], cell: 10);
      expect(map.distanceAt(const Offset(25, 25)), 0); // 글자 칸 안
      expect(map.distanceAt(const Offset(35, 25)), closeTo(10, 0.01)); // 한 칸 옆
      expect(map.distanceAt(const Offset(5, 25)), closeTo(20, 0.01)); // 두 칸 옆
    });

    test('거리 변환은 대각선도 잰다', () {
      final mask = Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0, 0]);
      final d = GuideMap.distanceCells(mask, 3, 3);
      expect(d[4], closeTo(1.4142, 0.001));
    });

    test('획을 칸 크기 간격으로 채운다', () {
      final points = StrokeMetrics.resample([
        [const Offset(0, 0), const Offset(10, 0)],
      ], 4);
      expect(points.length, 4); // 시작점 + 3칸
      expect(StrokeMetrics.resample([
        [const Offset(5, 5)],
      ], 4).length, 1);
    });
  });

  group('판정', () {
    test('제대로 따라 쓰면 통과하고 점수가 높다', () {
      final v = judge([
        [const Offset(34, 34), const Offset(118, 34), const Offset(118, 134)],
      ]);
      expect(v.passed, isTrue);
      expect(v.score, greaterThanOrEqualTo(95));
      expect(v.issue, isNull);
    });

    test('ㄱ 자리에 ㄴ을 쓰면 실패한다', () {
      final v = judge([
        [const Offset(40, 34), const Offset(40, 134), const Offset(118, 134)],
      ]);
      expect(v.passed, isFalse);
    });

    test('점 하나만 찍으면 실패한다', () {
      final v = judge([
        [const Offset(60, 36)],
      ]);
      expect(v.passed, isFalse);
      expect(v.score, lessThan(60));
    });

    test('절반 크기로 쓰면 크기를 고치라고 한다', () {
      final v = judge([
        [const Offset(57, 57), const Offset(99, 57), const Offset(99, 107)],
      ]);
      expect(v.passed, isFalse);
      expect(v.issue, PracticeIssue.size);
      expect(v.message, contains('작아요'));
    });

    test('가로획만 쓰고 세로획을 빼먹으면 덜 그려졌다고 한다', () {
      final v = judge([
        [const Offset(34, 34), const Offset(118, 34)],
      ]);
      expect(v.passed, isFalse);
      expect(v.issue, PracticeIssue.missing);
      expect(v.message, contains('덜 그려졌어요'));
    });

    test('연습하기(lenient)는 틀려도 통과로 본다', () {
      final report = StrokeMetrics.measure([
        [const Offset(60, 36)],
      ], giyeok());
      final v = PracticeJudge.judge(report, label: '기역', lenient: true);
      expect(v.passed, isTrue);
    });

    test('아무것도 안 쓰면 모두 0', () {
      final r = StrokeMetrics.measure([], giyeok());
      expect(r.inside, 0);
      expect(r.covered, 0);
    });
  });

  group('낱말', () {
    GuideMap two() {
      // 왼쪽 글자(칸 2~13)와 오른쪽 글자(칸 22~33), 높이 칸 5~14
      const cols = 40, rows = 20;
      final text = [
        for (var y = 0; y < rows; y++)
          [
            for (var x = 0; x < cols; x++)
              (y >= 5 && y <= 14 && ((x >= 2 && x <= 13) || (x >= 22 && x <= 33))) ? '#' : '.',
          ].join(),
      ];
      final base = GuideMap.fromAscii(text);
      return base.withUnits([
        GuideUnit(text: '가', box: const Rect.fromLTRB(0, 0, 80, 80), ink: const Rect.fromLTRB(8, 20, 56, 60)),
        GuideUnit(text: '나', box: const Rect.fromLTRB(80, 0, 160, 80), ink: const Rect.fromLTRB(88, 20, 136, 60)),
      ]);
    }

    test('오른쪽으로 갈수록 내려가면 기울기가 양수다', () {
      final r = StrokeMetrics.measure([
        [const Offset(10, 30), const Offset(50, 30), const Offset(50, 50)],
        [const Offset(100, 60), const Offset(140, 60), const Offset(140, 80)],
      ], two());
      expect(r.tiltDegrees, isNotNull);
      expect(r.tiltDegrees!, greaterThan(Thresholds.maxTiltDegrees));
    });

    test('음절이 하나면 기울기와 자간은 없다', () {
      final r = StrokeMetrics.measure([
        [const Offset(34, 34), const Offset(118, 34)],
      ], giyeok());
      expect(r.tiltDegrees, isNull);
      expect(r.spacingMin, isNull);
    });
  });
}

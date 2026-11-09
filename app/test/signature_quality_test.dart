import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/sign/signature_check.dart';

void main() {
  const guide = Rect.fromLTWH(0, 0, 100, 100);
  test(
    'separate signers are judged independently without inferring their identity',
    () {
      for (final count in [8, 1, 12, 2]) {
        final verdict = SignatureCheck.judge(_strokes(count), guide);
        expect(verdict.ok, isTrue, reason: verdict.message);
      }
    },
  );
  test(
    'explicit same-signer comparison still requires an explicit baseline',
    () {
      final baseline = SignatureCheck.judge(_strokes(8), guide).metrics;
      expect(
        SignatureCheck.judge(_strokes(1), guide, baseline: baseline).ok,
        isFalse,
      );
      expect(SignatureCheck.judge(_strokes(1), guide).ok, isTrue);
    },
  );
  test('empty ink remains rejected', () {
    expect(SignatureCheck.judge([], guide).ok, isFalse);
  });
  test('tiny ink remains rejected', () {
    expect(
      SignatureCheck.judge(_strokes(1, end: const Offset(25, 25)), guide).ok,
      isFalse,
    );
  });
  test('an accidental quick stroke remains rejected', () {
    expect(SignatureCheck.judge(_strokes(1, duration: 100), guide).ok, isFalse);
  });
  test('ink outside the writing surface remains rejected', () {
    expect(
      SignatureCheck.judge(_strokes(1, end: const Offset(110, 110)), guide).ok,
      isFalse,
    );
  });
}

List<List<PenPoint>> _strokes(
  int count, {
  Offset end = const Offset(80, 80),
  int duration = 600,
}) => [
  for (var i = 0; i < count; i++)
    [
      PenPoint(const Offset(20, 20), i * 1000, .5),
      PenPoint(end, i * 1000 + duration, .5),
    ],
];

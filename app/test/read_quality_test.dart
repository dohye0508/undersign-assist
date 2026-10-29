@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/read/read_panel.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/features/sign/signature_spots.dart';
import 'package:undersign_assist/models/recognized_document.dart';

void main() {
  final payload = <String, dynamic>{
    'doc_type': 'contract',
    'doc_type_label': '계약서',
    'needs_review': true,
    'review_pages': [1],
    'speech': '2페이지의 글자를 충분히 읽지 못했어요. 다시 찍어 주세요.',
    'blocks': [
      {'text': '성명: (서명)', 'box': {'x': 10, 'y': 10, 'width': 180, 'height': 25}, 'page': 1, 'confidence': 24.5},
    ],
    'fields': [{'label': '임금', 'value': '잘못 읽힌 금액', 'line': 0}],
  };

  test('quality metadata survives JSON and legacy results still load', () {
    final document = RecognizedDocument.fromJson(payload);
    final restored = RecognizedDocument.fromJson(document.toJson());
    expect(restored.needsReview, isTrue);
    expect(restored.reviewPages, [1]);
    expect(restored.blocks.single.confidence, 24.5);
    expect(RecognizedDocument.fromJson({}).needsReview, isFalse);
  });

  test('partial OCR does not suggest fill or signature targets', () {
    final document = RecognizedDocument.fromJson(payload);
    expect(findFillTargets(document), isEmpty);
    expect(findSignatureSpots(document), isEmpty);
    expect(describeDocument(document), document.speech);
  });

  testWidgets('read summary shows retake guidance instead of unreliable values', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReadSummary(document: RecognizedDocument.fromJson(payload)))));
    expect(find.textContaining('다시 찍어', findRichText: true), findsOneWidget);
    expect(find.text('잘못 읽힌 금액'), findsNothing);
  });
}

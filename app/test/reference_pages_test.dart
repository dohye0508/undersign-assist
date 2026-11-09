import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/features/sign/signature_spots.dart';
import 'package:undersign_assist/models/recognized_document.dart';

void main() {
  test('old backend responses keep normal fill and signature behavior', () {
    final json = _response()..remove('reference_pages');
    final document = RecognizedDocument.fromJson(json);
    expect(document.referencePages, isEmpty);
    expect(findFillTargets(document).map((t) => t.page).toSet(), {0, 1, 2});
    expect(findSignatureSpots(document).map((s) => s.page), [0, 1, 2]);
  });

  test(
    'guide pages stay readable but cannot become fill or signature targets',
    () {
      final document = RecognizedDocument.fromJson(_response());
      expect(document.referencePages, [1]);
      expect(document.toJson()['reference_pages'], [1]);
      expect(document.pages, hasLength(3));
      expect(document.blocks, hasLength(6));
      expect(document.blocks[2].text, '예시 성명:');
      expect(document.fullText, contains('예시 성명:'));
      final fills = findFillTargets(document);
      expect(fills.map((t) => t.page).toSet(), {0, 2});
      expect(fills.last.id, contains('p2-l5'));
      final signatures = findSignatureSpots(document);
      expect(signatures.map((s) => s.line), [1, 5]);
      expect(signatures.map((s) => s.page), [0, 2]);
    },
  );

  test(
    'the same form without guide metadata remains complete after JSON roundtrip',
    () {
      final json = _response()..['reference_pages'] = <int>[];
      final original = RecognizedDocument.fromJson(json);
      final copied = RecognizedDocument.fromJson(original.toJson());
      expect(
        findFillTargets(copied).map((t) => t.id),
        findFillTargets(original).map((t) => t.id),
      );
      expect(findSignatureSpots(copied).map((s) => s.line), [1, 3, 5]);
    },
  );
}

Map<String, dynamic> _response() => {
  'doc_type': 'application',
  'image_width': 600,
  'image_height': 800,
  'full_text': '성명:\n서명\n예시 성명:\n서명\n보호자 성명:\n서명',
  'pages': [
    for (var i = 0; i < 3; i++) {'width': 600, 'height': 800},
  ],
  'reference_pages': [1],
  'blocks': [
    for (var i = 0; i < 6; i++)
      {
        'text': ['성명:', '서명', '예시 성명:', '서명', '보호자 성명:', '서명'][i],
        'page': i ~/ 2,
        'box': {'x': 30, 'y': 50 + (i % 2) * 100, 'width': 120, 'height': 30},
      },
  ],
};

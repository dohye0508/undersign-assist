import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/services/api_client.dart';

const document = RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: [TextBlock('성명: 김가상', Box(0, 0, 90, 20))],
  fields: [],
  fullText: '성명: 김가상',
  imageWidth: 100,
  imageHeight: 200,
  pages: [PageSize(100, 200)],
  reader: 'rules',
  speech: '신청서예요.',
);
Map<String, dynamic> judgement({
  List<Object> findings = const [],
  Map<String, int> counts = const {},
  List<Object> questions = const [],
}) => {
  'findings': findings,
  'counts': counts,
  'questions': questions,
  'speech': '검토 결과예요.',
  'subtype': 'application',
  'disclaimer': '',
};
Future<T> respond<T>(Object body, Future<T> Function() action) =>
    http.runWithClient(
      action,
      () => MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

void main() {
  test(
    'reference page metadata preserves valid pages and rejects invalid indexes',
    () async {
      final photo = DocumentPhoto(
        name: 'synthetic.png',
        bytes: Uint8List.fromList([1]),
      );
      for (final index in [-1, 1]) {
        await expectLater(
          respond({
            ...document.toJson(),
            'reference_pages': [index],
          }, () => ApiClient.read([photo])),
          throwsA(isA<ApiException>()),
        );
      }
      final result = await respond({
        ...document.toJson(),
        'reference_pages': [0],
      }, () => ApiClient.read([photo]));
      expect(result.referencePages, [0]);
      expect(result.toJson()['reference_pages'], [0]);
      expect(result.blocks.single.text, document.blocks.single.text);
    },
  );
  final photo = DocumentPhoto(
    name: 'synthetic.png',
    bytes: Uint8List.fromList([1]),
  );
  for (final box in [
    const Box(-1, 0, 20, 10),
    const Box(95, 0, 20, 10),
    const Box(0, 195, 20, 10),
  ]) {
    test('read rejects out-of-photo geometry ${box.toJson()}', () async {
      final body = document.toJson()
        ..['blocks'] = [TextBlock('성명', box).toJson()];
      await expectLater(
        respond(body, () => ApiClient.read([photo])),
        throwsA(isA<ApiException>()),
      );
    });
  }

  test('a caution cannot be accepted with an all-clear count', () async {
    await expectLater(
      respond(
        judgement(
          findings: [
            {'level': 'caution', 'item': '금액 확인', 'line': 0},
          ],
        ),
        () => ApiClient.judge(document),
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test('negative counts cannot produce a misleading conclusion', () async {
    await expectLater(
      respond(
        judgement(counts: {'caution': -1}),
        () => ApiClient.judge(document),
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'unknown finding levels and dangling source references are rejected',
    () async {
      for (final finding in [
        {'level': 'clear', 'line': 0},
        {'level': 'caution', 'line': 4},
        {'level': 'caution', 'line': -2},
      ]) {
        await expectLater(
          respond(
            judgement(
              findings: [finding],
              counts: {finding['level'] as String: 1},
            ),
            () => ApiClient.judge(document),
          ),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
  test('questions must be answerable and have unique identifiers', () async {
    for (final questions in [
      [
        {'id': 'size', 'text': '확인했나요?', 'options': {}},
      ],
      [
        {
          'id': '',
          'text': '확인했나요?',
          'options': {'yes': '예'},
        },
      ],
      [
        {
          'id': 'size',
          'text': '',
          'options': {'yes': '예'},
        },
      ],
      [
        {
          'id': 'size',
          'text': '확인했나요?',
          'options': {'': '예'},
        },
      ],
      [
        {
          'id': 'size',
          'text': '확인했나요?',
          'options': {'yes': ''},
        },
      ],
      [
        for (var i = 0; i < 2; i++)
          {
            'id': 'size',
            'text': '확인했나요?',
            'options': {'yes': '예'},
          },
      ],
    ]) {
      await expectLater(
        respond(
          judgement(questions: questions),
          () => ApiClient.judge(document),
        ),
        throwsA(isA<ApiException>()),
      );
    }
  });
  test(
    'valid source-less findings and explicit zero counts remain supported',
    () async {
      final result = await respond(
        judgement(
          findings: [
            {'level': 'info', 'item': '자동 검토 불가', 'line': -1},
          ],
          counts: {'info': 1, 'caution': 0, 'missing': 0},
          questions: [
            {
              'id': 'size',
              'text': '확인했나요?',
              'options': {'yes': '예', 'unknown': '모름'},
            },
          ],
        ),
        () => ApiClient.judge(document),
      );
      expect(result.findings.single.line, -1);
      expect(result.questions.single.options['unknown'], '모름');
    },
  );
  test('writing check must describe the requested field', () async {
    final body = {
      'field': '주소',
      'found': true,
      'written': '가상 주소',
      'speech': '주소예요.',
    };
    await expectLater(
      respond(body, () => ApiClient.checkWriting(photo, '성명')),
      throwsA(isA<ApiException>()),
    );
    body['field'] = '성명';
    expect(
      (await respond(
        body,
        () => ApiClient.checkWriting(photo, ' 성명 '),
      ))['field'],
      '성명',
    );
  });
}

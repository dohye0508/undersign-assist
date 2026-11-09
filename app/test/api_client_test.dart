import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/models/workspace_state.dart';
import 'package:undersign_assist/services/api_client.dart';

DocumentPhoto photo(String name) =>
    DocumentPhoto(name: name, bytes: Uint8List.fromList([1, 2, 3]));
Map<String, dynamic> readBody({int pages = 1}) => {
  'doc_type': 'application',
  'doc_type_label': '신청서',
  'full_text': '신청서',
  'blocks': [],
  'fields': [],
  'pages': List.generate(pages, (_) => {'width': 100, 'height': 200}),
  'image_width': 100,
  'image_height': 200,
  'reader': 'rules',
  'speech': '신청서를 읽었어요.',
};
http.Response jsonResponse(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Matcher messageContains(String value) =>
    predicate((error) => error.toString().contains(value));

class StalledClient extends http.BaseClient {
  final waiting = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      waiting.future;
  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'legacy single-page dimensions still decode without pages metadata',
    () async {
      final body = readBody()..remove('pages');
      final result = await http.runWithClient(
        () => ApiClient.read([photo('a')]),
        () => MockClient((_) async => jsonResponse(body)),
      );
      expect(result.imageWidth, 100);
    },
  );

  test('invalid page geometry and dangling references are rejected', () async {
    final block = {
      'text': '성명',
      'box': {'x': 0, 'y': 0, 'width': 20, 'height': 10},
      'page': 2,
    };
    for (final override in [
      {
        'pages': [
          {'width': 0, 'height': 20},
        ],
      },
      {
        'blocks': [block],
      },
      {
        'fields': [
          {'label': '성명', 'value': '김가상', 'line': 4},
        ],
      },
      {
        'needs_review': false,
        'review_pages': [0],
      },
      {
        'needs_review': true,
        'review_pages': [2],
      },
    ]) {
      final body = {...readBody(), ...override};
      await expectLater(
        http.runWithClient(
          () => ApiClient.read([photo('a')]),
          () => MockClient((_) async => jsonResponse(body)),
        ),
        throwsA(messageContains('응답')),
      );
    }
  });

  test(
    'write check validates the response and preserves requested field',
    () async {
      final client = MockClient((request) async {
        expect(
          utf8.decode(request.bodyBytes, allowMalformed: true),
          contains('성명'),
        );
        return jsonResponse({
          'field': '성명',
          'found': false,
          'written': '',
          'speech': '칸을 찾지 못했어요.',
        });
      });
      final result = await http.runWithClient(
        () => ApiClient.checkWriting(photo('a'), '성명'),
        () => client,
      );
      expect(result['found'], isFalse);
      await expectLater(
        http.runWithClient(
          () => ApiClient.checkWriting(photo('a'), '성명'),
          () => MockClient((_) async => jsonResponse({})),
        ),
        throwsA(messageContains('응답')),
      );
    },
  );

  test('multipart preserves page order and UTF-8 read response', () async {
    final client = MockClient((request) async {
      final body = utf8.decode(request.bodyBytes, allowMalformed: true);
      expect(body.indexOf('first.jpg'), lessThan(body.indexOf('second.jpg')));
      expect(RegExp('name="photo"').allMatches(body).length, 2);
      return jsonResponse(readBody(pages: 2));
    });
    final result = await http.runWithClient(
      () => ApiClient.read([photo('first.jpg'), photo('second.jpg')]),
      () => client,
    );
    expect(result.docTypeLabel, '신청서');
    expect(result.pages.length, 2);
  });

  test('empty selection is rejected before upload', () async {
    var sent = false;
    final client = MockClient((_) async {
      sent = true;
      return jsonResponse(readBody());
    });
    await expectLater(
      http.runWithClient(() => ApiClient.read([]), () => client),
      throwsA(messageContains('사진')),
    );
    expect(sent, isFalse);
  });

  test(
    'a missing page in a successful response cannot become a partial document',
    () async {
      final client = MockClient((_) async => jsonResponse(readBody()));
      await expectLater(
        http.runWithClient(
          () => ApiClient.read([photo('a'), photo('b')]),
          () => client,
        ),
        throwsA(messageContains('응답')),
      );
    },
  );

  test('malformed or empty success bodies are errors', () async {
    for (final body in [
      '<html>maintenance</html>',
      '[]',
      'null',
      '{}',
      '{"doc_type":12}',
    ]) {
      final client = MockClient((_) async => http.Response(body, 200));
      await expectLater(
        http.runWithClient(() => ApiClient.read([photo('a')]), () => client),
        throwsA(messageContains('응답')),
      );
    }
  });

  test('safe upload validation detail reaches the user', () async {
    for (final code in [400, 413, 422]) {
      final client = MockClient(
        (_) async => jsonResponse({'detail': '사진 크기를 줄여 주세요.'}, code),
      );
      await expectLater(
        http.runWithClient(() => ApiClient.read([photo('a')]), () => client),
        throwsA(messageContains('사진 크기를 줄여 주세요.')),
      );
    }
  });

  test('validation arrays and internal server detail are not leaked', () async {
    for (final code in [422, 500, 502]) {
      final client = MockClient(
        (_) async => jsonResponse({
          'detail': code == 422
              ? [
                  {'input': 'private-value'},
                ]
              : 'private-value',
        }, code),
      );
      try {
        await http.runWithClient(
          () => ApiClient.read([photo('a')]),
          () => client,
        );
        fail('must reject the failed HTTP response');
      } catch (error) {
        expect(error.toString(), isNot(contains('private-value')));
        expect(error.toString(), isNot(contains('/api/read')));
      }
    }
  });

  test('connection failure becomes a retryable Korean message', () async {
    final client = MockClient(
      (_) async => throw http.ClientException('Failed to fetch secret-host'),
    );
    await expectLater(
      http.runWithClient(() => ApiClient.read([photo('a')]), () => client),
      throwsA(messageContains('연결')),
    );
  });

  test('judge posts the selected answers and rejects empty success', () async {
    final client = MockClient((request) async {
      expect(jsonDecode(request.body)['answers'], {'workplace_size': 'under5'});
      return jsonResponse({});
    });
    await expectLater(
      http.runWithClient(
        () => ApiClient.judge(
          RecognizedDocument.fromJson(readBody()),
          answers: {'workplace_size': 'under5'},
        ),
        () => client,
      ),
      throwsA(messageContains('응답')),
    );
  });

  test('workspace shows upload validation and can recover on retry', () async {
    var calls = 0;
    final state = WorkspaceState();
    addTearDown(state.dispose);
    state.addPage(photo('a'));
    await http.runWithClient(
      state.read,
      () => MockClient((_) async {
        calls++;
        return jsonResponse({'detail': '다른 사진을 선택해 주세요.'}, 400);
      }),
    );
    expect(state.reading, isFalse);
    expect(state.readError, contains('다른 사진'));
    await http.runWithClient(
      state.read,
      () => MockClient((_) async {
        calls++;
        return jsonResponse(readBody());
      }),
    );
    expect(calls, 2);
    expect(state.readError, isNull);
    expect(state.recognized?.docType, 'application');
  });

  testWidgets('stalled request releases loading and closes the connection', (
    tester,
  ) async {
    final client = StalledClient();
    final state = WorkspaceState();
    state.addPage(photo('a'));
    addTearDown(() {
      state.dispose();
      if (!client.waiting.isCompleted) {
        client.waiting.completeError(http.ClientException('test cleanup'));
      }
    });
    http.runWithClient(state.read, () => client);
    await tester.pump(const Duration(minutes: 4));
    expect(state.reading, isFalse);
    expect(state.readError, contains('시간'));
    expect(client.closed, isTrue);
  });

  testWidgets('deadline also covers a response body that never finishes', (
    tester,
  ) async {
    final stream = StreamController<List<int>>();
    final client = StalledClient();
    client.waiting.complete(http.StreamedResponse(stream.stream, 200));
    final state = WorkspaceState();
    state.addPage(photo('a'));
    addTearDown(() {
      state.dispose();
      stream.close();
    });
    http.runWithClient(state.read, () => client);
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));
    expect(state.reading, isFalse);
    expect(state.readError, contains('시간'));
    expect(client.closed, isTrue);
  });
}

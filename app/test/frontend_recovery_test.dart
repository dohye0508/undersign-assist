@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:undersign_assist/features/judge/judge_panel.dart';
import 'package:undersign_assist/features/read/read_panel.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/judgement.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/models/workspace_state.dart';
import 'package:undersign_assist/screens/workspace_screen.dart';
import 'package:undersign_assist/services/camera_service.dart';
import 'package:undersign_assist/services/haptics.dart';
import 'package:undersign_assist/services/speech.dart';

import 'fixtures/judgement_responses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Haptics.effectVolume = 0;
    Haptics.vibrationEnabled = false;
    Speech.lastMessage.value = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  testWidgets('read retry announces its recovered summary', (tester) async {
    var calls = 0;
    final state = WorkspaceState(
      readDocument: (_) async {
        if (calls++ == 0) throw TimeoutException('synthetic timeout');
        return _document();
      },
    );
    addTearDown(state.dispose);
    state.addPage(_photo('document'));
    await state.read();
    await _panel(tester, state, () => ReadPanel(state: state));
    Speech.lastMessage.value = '이전 오류';
    await tester.tap(find.text('다시 읽기'));
    await tester.pumpAndSettle();
    expect(find.text('신청서'), findsOneWidget);
    expect(Speech.lastMessage.value, _document().speech);
  });

  testWidgets(
    'judge retry announces the next question after a failed request',
    (tester) async {
      var calls = 0;
      final state = WorkspaceState(
        readDocument: (_) async => _document(),
        judgeDocument: (_, _) async {
          if (calls++ == 0) throw TimeoutException('synthetic timeout');
          return _judgement(question: true);
        },
      );
      addTearDown(state.dispose);
      state.addPage(_photo('document'));
      await state.read();
      await _panel(tester, state, () => JudgePanel(state: state));
      await tester.pumpAndSettle();
      expect(find.text('다시 검토하기'), findsOneWidget);
      Speech.lastMessage.value = '이전 오류';
      await tester.tap(find.text('다시 검토하기'));
      await tester.pumpAndSettle();
      expect(find.text('확인했나요?'), findsOneWidget);
      expect(Speech.lastMessage.value, contains('확인했나요?'));
    },
  );

  testWidgets(
    'an answer can still be changed after its failed request succeeds on retry',
    (tester) async {
      var calls = 0;
      final state = WorkspaceState(
        readDocument: (_) async => _document(),
        judgeDocument: (_, _) async {
          calls++;
          if (calls == 2) throw TimeoutException('synthetic answer timeout');
          return _judgement(question: true);
        },
      );
      addTearDown(state.dispose);
      state.addPage(_photo('document'));
      await state.read();
      await _panel(tester, state, () => JudgePanel(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('예'));
      await tester.pumpAndSettle();
      expect(find.text('다시 검토하기'), findsOneWidget);
      await tester.tap(find.text('다시 검토하기'));
      await tester.pumpAndSettle();
      expect(find.text('답 바꾸기'), findsOneWidget);
      await tester.tap(find.text('답 바꾸기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('아니요'));
      await tester.pumpAndSettle();
      expect(state.answers['confirmed'], 'no');
    },
  );

  for (final entry in incompleteJudgements.entries) {
    testWidgets(
      '${entry.key} incomplete result is never displayed or spoken as all-clear',
      (tester) async {
        var calls = 0;
        final state = WorkspaceState(
          readDocument: (_) async => _document(),
          judgeDocument: (_, _) async {
            return calls++ == 0
                ? _judgement(question: true)
                : Judgement.fromJson(entry.value);
          },
        );
        addTearDown(state.dispose);
        state.addPage(_photo('document'));
        await state.read();
        await _panel(tester, state, () => JudgePanel(state: state));
        await tester.pumpAndSettle();
        await tester.tap(find.text('예'));
        await tester.pumpAndSettle();
        expect(find.text('특별히 확인할 것이 없어요.'), findsNothing);
        expect(Speech.lastMessage.value, isNot(contains('특별히 확인할 것이 없어요')));
        expect(
          Speech.lastMessage.value,
          contains(entry.key == 'unknown' ? '완료하지 못했어요' : '읽지 못한 항목'),
        );
      },
    );
  }

  testWidgets('photo picker failure is announced and a second attempt works', (
    tester,
  ) async {
    final state = WorkspaceState();
    final camera = _Camera();
    addTearDown(state.dispose);
    addTearDown(camera.dispose);
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          state: state,
          camera: camera,
          pickImages: () async {
            if (attempts++ == 0) throw StateError('synthetic picker failure');
            return [
              XFile.fromData(Uint8List.fromList([1]), name: 'retry.png'),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 불러오기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(Speech.lastMessage.value, contains('불러오지 못했어요'));
    await tester.tap(find.text('사진 불러오기'));
    await tester.pumpAndSettle();
    expect(state.pages.single.name, 'retry.png');
  });

  testWidgets(
    'a failed batch preserves existing pages without importing only its first file',
    (tester) async {
      final state = WorkspaceState()..addPage(_photo('original'));
      final camera = _Camera();
      addTearDown(state.dispose);
      addTearDown(camera.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceScreen(
            state: state,
            camera: camera,
            pickImages: () async => [
              XFile.fromData(Uint8List.fromList([1]), name: 'first.png'),
              _BrokenFile(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('사진 불러오기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(state.pages.map((p) => p.name), ['original']);
      expect(Speech.lastMessage.value, contains('불러오지 못했어요'));
    },
  );

  testWidgets(
    'analysis waits for the complete photo batch and starts normally afterward',
    (tester) async {
      var reads = 0;
      final state = WorkspaceState(
        readDocument: (_) async {
          reads++;
          return _document();
        },
      )..addPage(_photo('original'));
      final camera = _Camera();
      final bytes = Completer<Uint8List>();
      addTearDown(state.dispose);
      addTearDown(camera.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceScreen(
            state: state,
            camera: camera,
            pickImages: () async => [_PendingFile(bytes.future)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('사진 불러오기'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(reads, 0);
      bytes.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(state.pages, hasLength(2));
      await tester.tap(find.text('분석하기 (2장)'));
      await tester.pumpAndSettle();
      expect(reads, 1);
    },
  );
}

Future<void> _panel(
  WidgetTester tester,
  WorkspaceState state,
  Widget Function() panel,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: state,
        builder: (_, _) => SingleChildScrollView(child: panel()),
      ),
    ),
  ),
);

RecognizedDocument _document() => const RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: [],
  fields: [],
  fullText: '',
  imageWidth: 100,
  imageHeight: 100,
  pages: [PageSize(100, 100)],
  reader: 'rules',
  speech: '다시 읽은 신청서예요.',
);

Judgement _judgement({bool question = false}) => Judgement(
  findings: const [],
  speech: '검토가 끝났어요.',
  subtype: 'application',
  counts: const {},
  disclaimer: '',
  questions: question
      ? const [
          Question(
            id: 'confirmed',
            text: '확인했나요?',
            options: {'yes': '예', 'no': '아니요'},
          ),
        ]
      : const [],
);

DocumentPhoto _photo(String name) =>
    DocumentPhoto(bytes: Uint8List.fromList([1]), name: name);

class _Camera extends CameraService {
  @override
  bool get ready => true;
  @override
  Future<void> start() async {}
  @override
  Widget preview() => const SizedBox.expand();
}

class _BrokenFile extends XFile {
  _BrokenFile() : super('broken.png');
  @override
  Future<Uint8List> readAsBytes() async =>
      throw StateError('synthetic file read failure');
}

class _PendingFile extends XFile {
  _PendingFile(this.bytes) : super('pending.png');
  final Future<Uint8List> bytes;
  @override
  Future<Uint8List> readAsBytes() => bytes;
}

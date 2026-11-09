@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/practice/practice_home.dart';
import 'package:undersign_assist/features/practice/score_store.dart';
import 'package:undersign_assist/features/settings/settings_screen.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/models/workspace_state.dart';
import 'package:undersign_assist/screens/workspace_screen.dart';
import 'package:undersign_assist/services/camera_service.dart';
import 'package:undersign_assist/services/haptics.dart';
import 'package:undersign_assist/services/speech.dart';
import 'package:undersign_assist/widgets/page_tray.dart';
import 'package:undersign_assist/widgets/panel_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Haptics.effectVolume = 0;
    Haptics.vibrationEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  testWidgets(
    'a pending capture blocks duplicate shots, import and premature analysis',
    (tester) async {
      final captured = Completer<DocumentPhoto?>();
      var shots = 0, reads = 0, picks = 0;
      final camera = _Camera(() {
        shots++;
        return captured.future;
      });
      final state = WorkspaceState(
        readDocument: (_) async {
          reads++;
          return _document;
        },
      )..addPage(_photo('first'));
      addTearDown(camera.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceScreen(
            camera: camera,
            state: state,
            pickImages: () async {
              picks++;
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(shots, 1);
      expect(picks, 0);
      expect(reads, 0);
      captured.complete(_photo('second'));
      await tester.pumpAndSettle();
      expect(state.pages.map((p) => p.name), ['first', 'second']);
      await tester.tap(find.text('분석하기 (2장)'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(state.recognized, isNotNull);
    },
  );

  testWidgets('a capture failure is announced and releases the next capture', (
    tester,
  ) async {
    var shots = 0;
    final camera = _Camera(() async {
      if (shots++ == 0) throw StateError('synthetic camera failure');
      return _photo('retry');
    });
    final state = WorkspaceState();
    addTearDown(camera.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(camera: camera, state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(Speech.lastMessage.value, contains('찍지 못했어요'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(state.pages.single.name, 'retry');
  });

  testWidgets(
    'a capture completing after the screen closes cannot add a page',
    (tester) async {
      final captured = Completer<DocumentPhoto?>();
      final camera = _Camera(() => captured.future);
      final state = WorkspaceState();
      addTearDown(camera.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceScreen(camera: camera, state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpWidget(const SizedBox.shrink());
      captured.complete(_photo('late'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(state.pages, isEmpty);
    },
  );

  testWidgets(
    'leaving analysis keeps camera guidance when reading later finishes',
    (tester) async {
      final read = Completer<RecognizedDocument>();
      final camera = _Camera(() async => null);
      final state = WorkspaceState(readDocument: (_) => read.future)
        ..addPage(_photo('first'));
      addTearDown(camera.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceScreen(camera: camera, state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final cameraGuidance = Speech.lastMessage.value;
      expect(cameraGuidance, contains('카메라로 돌아왔어요'));
      read.complete(_document);
      await tester.pumpAndSettle();
      expect(Speech.lastMessage.value, cameraGuidance);
    },
  );

  testWidgets('screen reader can invoke a next-step button', (tester) async {
    await _withSemantics(tester, () async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NextStepButton(
              title: '검토하세요',
              subtitle: '빠진 항목 확인',
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      _activate(tester, '검토하세요. 빠진 항목 확인');
      expect(calls, 1);
    });
  });

  testWidgets(
    'camera actions expose enabled taps and disable them while capturing',
    (tester) async {
      await _withSemantics(tester, () async {
        final captured = Completer<DocumentPhoto?>();
        final camera = _Camera(() => captured.future);
        final state = WorkspaceState();
        addTearDown(camera.dispose);
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: WorkspaceScreen(camera: camera, state: state),
          ),
        );
        await tester.pumpAndSettle();
        expect(_canTap(tester, '사진 불러오기'), isTrue);
        expect(_canTap(tester, '분석하기'), isFalse);
        _activate(tester, '찍기');
        await tester.pump();
        expect(_canTap(tester, '찍기'), isFalse);
        expect(_canTap(tester, '사진 불러오기'), isFalse);
        captured.complete(_photo('captured'));
        await tester.pumpAndSettle();
        expect(_canTap(tester, '분석하기 (1장)'), isTrue);
      });
    },
  );

  testWidgets(
    'screen reader can open page controls, remove one page and clear all',
    (tester) async {
      await _withSemantics(tester, () async {
        var toggles = 0, removed = -1, clears = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageTray(
                pages: [_photo('first')],
                open: true,
                onToggle: () => toggles++,
                onRemove: (index) => removed = index,
                onClearAll: () => clears++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _activate(tester, '업로드한 페이지 1장, 목록 닫기');
        _activate(tester, '1페이지 사진. 누르면 지워요');
        _activate(tester, '찍은 페이지 모두 지우기');
        expect(toggles, 1);
        expect(removed, 0);
        expect(clears, 1);
      });
    },
  );

  testWidgets('screen reader can choose speech speed from settings', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      _activate(tester, RegExp('말하기 속도. 지금은'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('아주 빠르게'));
      await tester.pumpAndSettle();
      _activate(tester, '말하기 속도 아주 빠르게');
      await tester.pumpAndSettle();
      expect(Speech.lastMessage.value, contains('말하기 속도를 아주 빠르게로 바꿨어요'));
    });
  });

  testWidgets('screen reader can open practice menus and save a profile', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      final store = ScoreStore(MemoryStorage());
      addTearDown(store.dispose);
      await tester.pumpWidget(MaterialApp(home: PracticeFlow(store: store)));
      await tester.pumpAndSettle();
      _activate(tester, RegExp('^내 정보 등록\\.'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byType(TextField).first)
            .getSemanticsData()
            .label,
        contains('이름'),
      );
      await tester.enterText(find.byType(TextField).first, '가상사용자');
      await tester.ensureVisible(find.text('저장'));
      await tester.pumpAndSettle();
      _activate(tester, '내 정보 저장');
      await tester.pumpAndSettle();
      expect(store.name, '가상사용자');
      _activate(tester, RegExp('^학습하기\\.'));
      await tester.pumpAndSettle();
      expect(_canTap(tester, RegExp('^자음\\.')), isTrue);
      _activate(tester, RegExp('^자음\\.'));
      await tester.pumpAndSettle();
      _activate(tester, '학습하기 돌아가기');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _activate(tester, '받아쓰기 돌아가기');
      await tester.pumpAndSettle();
      expect(find.text('학습하기'), findsOneWidget);
    });
  });
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    // Flutter verifies handles before package:test's addTearDown callbacks.
    handle.dispose();
  }
}

void _activate(WidgetTester tester, Pattern label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '$label must be actionable',
  );
  node.owner!.performAction(node.id, SemanticsAction.tap);
}

bool _canTap(WidgetTester tester, Pattern label) => tester
    .getSemantics(find.bySemanticsLabel(label))
    .getSemanticsData()
    .hasAction(SemanticsAction.tap);

DocumentPhoto _photo(String name) => DocumentPhoto(
  name: name,
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP8//8/AwMDEwMYAAAkBgMBXaJOiAAAAABJRU5ErkJggg==',
  ),
);

const _document = RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: [],
  fields: [],
  fullText: '',
  imageWidth: 100,
  imageHeight: 100,
  pages: [PageSize(100, 100)],
  reader: 'rules',
  speech: '새 문서를 읽었어요.',
);

class _Camera extends CameraService {
  _Camera(this.capture);
  final Future<DocumentPhoto?> Function() capture;
  @override
  bool get ready => true;
  @override
  Future<void> start() async {}
  @override
  Future<DocumentPhoto?> snapshot() => capture();
  @override
  Widget preview() => const SizedBox.expand();
}

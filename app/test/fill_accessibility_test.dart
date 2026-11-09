@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/fill_panel.dart';
import 'package:undersign_assist/features/fill/fill_screen.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/fill.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/models/workspace_state.dart';
import 'package:undersign_assist/services/haptics.dart';
import 'package:undersign_assist/services/speech.dart';

void main() {
  setUp(() {
    Haptics.effectVolume = 0;
    Haptics.vibrationEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  for (final filled in [true, false]) {
    testWidgets(
      'screen reader opens a ${filled ? 'filled' : 'blank'} field exactly once',
      (tester) async {
        final semantics = tester.ensureSemantics();
        addTearDown(semantics.dispose);
        final state = WorkspaceState(readDocument: (_) async => _document);
        addTearDown(state.dispose);
        final png = base64Decode(_png);
        state.addPage(DocumentPhoto(bytes: png, name: 'synthetic.png'));
        await state.read();
        final targets = findFillTargets(_document);
        expect(targets, hasLength(2));
        state.setFill(FilledInk(target: targets.first, png: png));
        final observer = _Routes();
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Scaffold(
              body: SingleChildScrollView(child: FillPanel(state: state)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = filled
            ? '${targets.first.label}, 채웠어요. 누르면 다시 써요.'
            : '${targets.last.label}, 아직 비었어요. 누르면 써요.';
        final finder = find.bySemanticsLabel(label);
        expect(finder, findsOneWidget);
        final node = tester.getSemantics(finder);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        final before = observer.pushes;
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byType(FillScreen), findsOneWidget);
        expect(observer.pushes, before + 1);
        expect(
          tester.widget<FillScreen>(find.byType(FillScreen)).start,
          filled ? 0 : 1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a new document does not inherit the previous signers stroke count',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      for (final strokeCount in [8, 1]) {
        final document = RecognizedDocument.fromJson({
          ..._document.toJson(),
          'blocks': [
            {
              'text': '서명',
              'page': 0,
              'box': {'x': 100, 'y': 200, 'width': 120, 'height': 30},
            },
          ],
        });
        final state = WorkspaceState(readDocument: (_) async => document);
        addTearDown(state.dispose);
        state.addPage(
          DocumentPhoto(
            bytes: base64Decode(_png),
            name: 'document-$strokeCount.png',
          ),
        );
        await state.read();
        final targets = findFillTargets(document);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(strokeCount),
            home: FillScreen(state: state, targets: targets),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.bySemanticsLabel(RegExp(r'서명 쓰는 칸\.'));
        expect(surface, findsOneWidget);
        final area = tester.getRect(surface);
        final start = area.topLeft + Offset(area.width * .2, area.height * .2);
        final end = area.topLeft + Offset(area.width * .8, area.height * .8);
        for (var i = 0; i < strokeCount; i++) {
          final gesture = await tester.createGesture(pointer: i + 20);
          await gesture.down(
            start,
            timeStamp: Duration(milliseconds: i * 1000),
          );
          await gesture.moveTo(
            end,
            timeStamp: Duration(milliseconds: i * 1000 + 600),
          );
          await gesture.up(timeStamp: Duration(milliseconds: i * 1000 + 700));
        }
        await tester.pump();
        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(Speech.lastMessage.value, isNot(contains('획 수가 많이 달라요')));
        // A valid signature enters PNG creation/placement. A rejected one leaves
        // Next enabled with an error, before any browser image work is needed.
        final next = find.widgetWithText(FilledButton, '다음');
        expect(tester.widget<FilledButton>(next).onPressed, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

const _document = RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: [
    TextBlock('성명:', Box(20, 80, 100, 30)),
    TextBlock('주소:', Box(20, 160, 100, 30)),
  ],
  fields: [],
  fullText: '성명:\n주소:',
  imageWidth: 600,
  imageHeight: 800,
  pages: [PageSize(600, 800)],
  reader: 'rules',
  speech: '신청서예요.',
);

// A synthetic transparent 1 x 1 PNG, with no user document or signature data.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

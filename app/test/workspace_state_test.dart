import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/judgement.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/models/workspace_state.dart';

DocumentPhoto photo(String name) =>
    DocumentPhoto(bytes: Uint8List.fromList([1]), name: name);
RecognizedDocument document(String name) =>
    RecognizedDocument.fromJson({'doc_type': name});
Judgement judgement(String name) => Judgement.fromJson({'subtype': name});

void main() {
  test(
    'changing photos ignores an old read and keeps the newer request busy',
    () async {
      final requests = <Completer<RecognizedDocument>>[];
      final inputs = <List<DocumentPhoto>>[];
      final state = WorkspaceState(
        readDocument: (pages) {
          inputs.add(pages);
          final request = Completer<RecognizedDocument>();
          requests.add(request);
          return request.future;
        },
      );
      addTearDown(state.dispose);
      state.addPage(photo('old'));
      final old = state.read();
      state.clearPages();
      expect(state.reading, isFalse);
      state.addPage(photo('new'));
      final current = state.read();
      expect(inputs.first.single.name, 'old');
      requests.first.complete(document('old'));
      expect(await old, isNull);
      expect(state.recognized, isNull);
      expect(state.reading, isTrue);
      requests.last.complete(document('new'));
      expect((await current)?.docType, 'new');
      expect(state.recognized?.docType, 'new');
      expect(state.reading, isFalse);
    },
  );

  test('adding or removing a page invalidates outstanding reads', () async {
    for (final add in [true, false]) {
      final request = Completer<RecognizedDocument>();
      final state = WorkspaceState(readDocument: (_) => request.future);
      state.addPage(photo('first'));
      state.addPage(photo('second'));
      final reading = state.read();
      if (add) {
        state.addPage(photo('third'));
      } else {
        state.removePage(0);
      }
      request.complete(document('obsolete'));
      expect(await reading, isNull);
      expect(state.recognized, isNull);
      state.dispose();
    }
  });

  test(
    'concurrent reads share one API request and a failed read can retry',
    () async {
      final requests = <Completer<RecognizedDocument>>[];
      final state = WorkspaceState(
        readDocument: (_) {
          final request = Completer<RecognizedDocument>();
          requests.add(request);
          return request.future;
        },
      );
      addTearDown(state.dispose);
      state.addPage(photo('first'));
      final first = state.read();
      final duplicate = state.read();
      expect(requests, hasLength(1));
      requests.first.completeError(Exception('offline'));
      expect(await first, isNull);
      expect(await duplicate, isNull);
      expect(state.readError, isNotNull);
      expect(state.reading, isFalse);
      final retry = state.read();
      expect(requests, hasLength(2));
      requests.last.complete(document('receipt'));
      expect((await retry)?.docType, 'receipt');
      expect(state.readError, isNull);
      expect((await state.read())?.docType, 'receipt');
      expect(requests, hasLength(2));
    },
  );

  test(
    'replacing photos ignores a previous judgement and its late error',
    () async {
      for (final fail in [false, true]) {
        final requests = <Completer<Judgement>>[];
        final state = WorkspaceState(
          readDocument: (pages) async => document(pages.single.name),
          judgeDocument: (_, answers) {
            final request = Completer<Judgement>();
            requests.add(request);
            return request.future;
          },
        );
        state.addPage(photo('old'));
        await state.read();
        final old = state.judge();
        state.clearPages();
        expect(state.judging, isFalse);
        state.addPage(photo('new'));
        await state.read();
        final current = state.judge();
        if (fail) {
          requests.first.completeError(Exception('old connection failed'));
        } else {
          requests.first.complete(judgement('old'));
        }
        expect(await old, isNull);
        expect(state.judgement, isNull);
        expect(state.judgeError, isNull);
        expect(state.judging, isTrue);
        requests.last.complete(judgement('new'));
        expect((await current)?.subtype, 'new');
        expect(state.judgement?.subtype, 'new');
        state.dispose();
      }
    },
  );

  test('changed answers use snapshots and newest judgement wins', () async {
    final requests = <Completer<Judgement>>[];
    final inputs = <Map<String, String>>[];
    final state = WorkspaceState(
      readDocument: (_) async => document('contract'),
      judgeDocument: (_, answers) {
        inputs.add(answers);
        final request = Completer<Judgement>();
        requests.add(request);
        return request.future;
      },
    );
    addTearDown(state.dispose);
    state.addPage(photo('first'));
    await state.read();
    final first = state.answer('employees', 'under5');
    final current = state.answer('employees', 'atLeast5');
    expect(inputs.first, {'employees': 'under5'});
    requests.last.complete(judgement('atLeast5'));
    expect((await current)?.subtype, 'atLeast5');
    requests.first.complete(judgement('under5'));
    expect(await first, isNull);
    expect(state.judgement?.subtype, 'atLeast5');
  });

  test('obsolete read errors cannot replace a newer successful read', () async {
    final requests = <Completer<RecognizedDocument>>[];
    final state = WorkspaceState(
      readDocument: (_) {
        final request = Completer<RecognizedDocument>();
        requests.add(request);
        return request.future;
      },
    );
    addTearDown(state.dispose);
    state.addPage(photo('old'));
    final old = state.read();
    state.clearPages();
    state.addPage(photo('new'));
    final current = state.read();
    requests.last.complete(document('new'));
    await current;
    requests.first.completeError(Exception('old request failed'));
    expect(await old, isNull);
    expect(state.recognized?.docType, 'new');
    expect(state.readError, isNull);
    expect(state.reading, isFalse);
  });

  test(
    'duplicate judgements share a request, retry errors, and cache identical answers',
    () async {
      final requests = <Completer<Judgement>>[];
      final state = WorkspaceState(
        readDocument: (_) async => document('contract'),
        judgeDocument: (_, answers) {
          final request = Completer<Judgement>();
          requests.add(request);
          return request.future;
        },
      );
      addTearDown(state.dispose);
      state.addPage(photo('first'));
      await state.read();
      final first = state.answer('employees', 'under5');
      final duplicate = state.answer('employees', 'under5');
      final duplicateJudge = state.judge();
      expect(requests, hasLength(1));
      requests.first.completeError(Exception('offline'));
      expect(await first, isNull);
      expect(await duplicate, isNull);
      expect(await duplicateJudge, isNull);
      expect(state.judgeError, isNotNull);
      expect(state.judging, isFalse);
      final retry = state.judge();
      expect(requests, hasLength(2));
      requests.last.complete(judgement('under5'));
      expect((await retry)?.subtype, 'under5');
      expect(state.judgeError, isNull);
      expect((await state.answer('employees', 'under5'))?.subtype, 'under5');
      expect(requests, hasLength(2));
    },
  );

  test(
    'disposed workspaces ignore pending read and judge completions',
    () async {
      final readRequest = Completer<RecognizedDocument>();
      final readState = WorkspaceState(readDocument: (_) => readRequest.future);
      readState.addPage(photo('first'));
      final reading = readState.read();
      readState.dispose();
      readRequest.complete(document('old'));
      expect(await reading, isNull);
      expect(await readState.read(), isNull);

      final judgeRequest = Completer<Judgement>();
      final judgeState = WorkspaceState(
        readDocument: (_) async => document('contract'),
        judgeDocument: (_, answers) => judgeRequest.future,
      );
      judgeState.addPage(photo('first'));
      await judgeState.read();
      final judging = judgeState.judge();
      judgeState.dispose();
      judgeRequest.completeError(Exception('late failure'));
      expect(await judging, isNull);
      expect(await judgeState.judge(), isNull);
    },
  );
}

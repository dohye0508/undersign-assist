@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/services/camera_service.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'a permission response after disposal stops every acquired track',
    () async {
      final response = Completer<web.MediaStream>();
      var stops = 0;
      final camera = CameraService(requestStream: (_) => response.future);
      final opening = camera.start();
      camera.dispose();
      response.complete(_stream(() => stops++, tracks: 2));
      await opening;
      expect(stops, 2);
      expect(camera.ready, isFalse);
      expect(await camera.snapshot(), isNull);
    },
  );

  test(
    'a rejected permission after disposal does not retry or notify',
    () async {
      final response = Completer<web.MediaStream>();
      var requests = 0;
      final camera = CameraService(
        requestStream: (_) {
          requests++;
          return response.future;
        },
      );
      final opening = camera.start();
      camera.dispose();
      response.completeError(StateError('synthetic permission failure'));
      await opening;
      await camera.start();
      expect(requests, 1);
      expect(camera.error, isNull);
    },
  );

  test(
    'a superseded permission response cannot replace the latest request',
    () async {
      final first = Completer<web.MediaStream>();
      final second = Completer<web.MediaStream>();
      var requests = 0;
      var stops = 0;
      final camera = CameraService(
        requestStream: (_) => requests++ == 0 ? first.future : second.future,
      );
      final opening = camera.start();
      final reopening = camera.start();
      first.complete(_stream(() => stops++));
      await opening;
      expect(stops, 1);
      expect(camera.ready, isFalse);
      expect(camera.error, isNull);
      camera.dispose();
      second.complete(_stream(() => stops++));
      await reopening;
      expect(stops, 2);
      expect(requests, 2);
    },
  );
}

// A structural browser stream is enough to observe lifecycle cleanup; no real
// camera permission or device is needed for an already-cancelled request.
web.MediaStream _stream(void Function() stop, {int tracks = 1}) {
  final entries = List.generate(tracks, (_) {
    final track = JSObject();
    track.setProperty('stop'.toJS, stop.toJS);
    return track;
  });
  final stream = JSObject();
  stream.setProperty('getTracks'.toJS, (() => entries.toJS).toJS);
  return stream as web.MediaStream;
}

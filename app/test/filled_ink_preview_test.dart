import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/filled_ink_preview.dart';
import 'package:undersign_assist/models/fill.dart';
import 'package:undersign_assist/models/recognized_document.dart';

void main() {
  for (final signature in [false, true]) {
    testWidgets('preview uses PDF inset for signature=$signature', (
      tester,
    ) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawRect(const ui.Rect.fromLTWH(0, 0, 80, 20), ui.Paint());
      final picture = recorder.endRecording();
      final raster = await tester.runAsync(() => picture.toImage(80, 20));
      final data = await tester.runAsync(
        () => raster!.toByteData(format: ui.ImageByteFormat.png),
      );
      final ink = data!.buffer.asUint8List();
      raster!.dispose();
      picture.dispose();
      final fill = FilledInk(
        target: FillTarget(
          id: 'test',
          label: signature ? '서명' : '성명',
          page: 0,
          rect: const Box(0, 0, 200, 100),
          isSignature: signature,
        ),
        png: ink,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 100,
                child: FilledInkPreview(fill: fill),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(FilledInkPreview));
      final image = tester.getTopLeft(find.byType(Image));
      expect(image.dx - origin.dx, signature ? 0 : 15);
      expect(tester.getSize(find.byType(Image)).width, signature ? 200 : 185);
    });
  }
}

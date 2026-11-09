import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:undersign_assist/features/output/signed_pdf.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/fill.dart';
import 'package:undersign_assist/models/recognized_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cropped signature is centered horizontally inside its fill target',
    () async {
      final pdf = await _filledPdf(
        signature: true,
        inkWidth: 20,
        inkHeight: 80,
      );
      final ink = _imageMatrices(pdf).last;
      final scale = PdfPageFormat.a4.width / 1000;
      // The 25 x 100 image belongs at x=187.5 inside the 200 x 100 target.
      expect(ink[0], closeTo(25 * scale, 0.001));
      expect(ink[3], closeTo(100 * scale, 0.001));
      expect(ink[4], closeTo(187.5 * scale, 0.001));
      expect(ink[5], closeTo(700 * scale, 0.001));
    },
  );

  test(
    'short handwritten text keeps its left inset and vertical center',
    () async {
      final pdf = await _filledPdf(
        signature: false,
        inkWidth: 80,
        inkHeight: 20,
      );
      final ink = _imageMatrices(pdf).last;
      final scale = PdfPageFormat.a4.width / 1000;
      // The 15px text inset leaves a 185 x 100 target for 185 x 46.25 ink.
      expect(ink[0], closeTo(185 * scale, 0.001));
      expect(ink[3], closeTo(46.25 * scale, 0.001));
      expect(ink[4], closeTo(115 * scale, 0.001));
      expect(ink[5], closeTo((750 - 46.25 / 2) * scale, 0.001));
    },
  );
  test(
    'different page sizes keep ink on its own page at that page scale',
    () async {
      final pdf = await buildSignedPdf(
        pages: [
          DocumentPhoto(bytes: await _png(100, 150), name: 'portrait.png'),
          DocumentPhoto(bytes: await _png(120, 80), name: 'landscape.png'),
        ],
        document: _document([
          const PageSize(1000, 1500),
          const PageSize(1200, 800),
        ]),
        signatures: const {},
        fills: [
          FilledInk(
            target: const FillTarget(
              id: 'page-two-signature',
              label: '2페이지 서명',
              page: 1,
              rect: Box(100, 200, 200, 100),
              isSignature: true,
            ),
            png: await _png(80, 20),
          ),
        ],
      );
      final images = _imageMatrices(pdf);
      expect(
        images,
        hasLength(3),
      ); // First photo, second photo, second-page ink.
      final width = PdfPageFormat.a4.width;
      expect(images[0][3], closeTo(width * 1.5, 0.001));
      expect(images[1][3], closeTo(width * 800 / 1200, 0.001));
      final ink = images.last;
      final scale = width / 1200;
      expect(ink[0], closeTo(200 * scale, 0.001));
      expect(ink[3], closeTo(50 * scale, 0.001));
      expect(ink[4], closeTo(100 * scale, 0.001));
      expect(ink[5], closeTo(525 * scale, 0.001));
    },
  );

  test('legacy signature also centers cropped ink over its keyword', () async {
    final pdf = await buildSignedPdf(
      pages: [
        DocumentPhoto(bytes: await _png(100, 100), name: 'synthetic.png'),
      ],
      document: _document(
        [const PageSize(1000, 1000)],
        blocks: [const TextBlock('서명', Box(100, 200, 200, 40))],
      ),
      signatures: {0: await _png(20, 20)},
    );
    final ink = _imageMatrices(pdf).last;
    final scale = PdfPageFormat.a4.width / 1000;
    expect(ink[0], closeTo(88 * scale, 0.001));
    expect(ink[3], closeTo(88 * scale, 0.001));
    expect(ink[4], closeTo(156 * scale, 0.001));
    expect(ink[5], closeTo(736 * scale, 0.001));
  });
}

Future<Uint8List> _filledPdf({
  required bool signature,
  required int inkWidth,
  required int inkHeight,
}) async {
  final photo = await _png(100, 100);
  return buildSignedPdf(
    pages: [DocumentPhoto(bytes: photo, name: 'synthetic.png')],
    document: _document([const PageSize(1000, 1000)]),
    signatures: const {},
    fills: [
      FilledInk(
        target: FillTarget(
          id: 'synthetic-fill',
          label: signature ? '서명' : '성명',
          page: 0,
          rect: const Box(100, 200, 200, 100),
          isSignature: signature,
        ),
        png: await _png(inkWidth, inkHeight),
      ),
    ],
  );
}

RecognizedDocument _document(
  List<PageSize> pages, {
  List<TextBlock> blocks = const [],
}) => RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: blocks,
  fields: const [],
  fullText: '',
  imageWidth: 1000,
  imageHeight: 1000,
  pages: pages,
  reader: 'rules',
  speech: '',
);

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

// Read actual PDF drawing commands, not the widget implementation's estimates.
// PDF image matrices map the image unit square into bottom-left page coordinates.
List<List<double>> _imageMatrices(Uint8List pdf) {
  final result = <List<double>>[];
  final streams = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
  final operators = RegExp(
    r'\b(q|Q)\b|([-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+) cm|/\S+ Do',
  );
  for (final match in streams.allMatches(latin1.decode(pdf))) {
    final raw = latin1.encode(match.group(1)!);
    String commands;
    try {
      commands = latin1.decode(zlib.decode(raw));
    } on FormatException {
      commands = latin1.decode(raw);
    }
    var matrix = <double>[1, 0, 0, 1, 0, 0];
    final saved = <List<double>>[];
    for (final op in operators.allMatches(commands)) {
      if (op.group(1) == 'q') {
        saved.add(matrix);
      } else if (op.group(1) == 'Q') {
        matrix = saved.removeLast();
      } else if (op.group(2) case final transform?) {
        final n = transform.split(' ').map(double.parse).toList();
        final m = matrix;
        matrix = [
          m[0] * n[0] + m[2] * n[1],
          m[1] * n[0] + m[3] * n[1],
          m[0] * n[2] + m[2] * n[3],
          m[1] * n[2] + m[3] * n[3],
          m[0] * n[4] + m[2] * n[5] + m[4],
          m[1] * n[4] + m[3] * n[5] + m[5],
        ];
      } else {
        result.add(matrix);
      }
    }
  }
  expect(
    result,
    isNotEmpty,
    reason: 'The exported PDF must draw its photo and ink.',
  );
  return result;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:undersign_assist/features/fill/fill_kind.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/features/output/signed_pdf.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/fill.dart';
import 'package:undersign_assist/models/recognized_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('empty and whitespace-only OCR do not invent fields', () {
    expect(findFillTargets(_doc([])), isEmpty);
    expect(
      findFillTargets(_doc([const TextBlock('  \n\t ', Box(0, 0, 30, 20))])),
      isEmpty,
    );
  });

  test(
    'already printed values stay untouched while blank names remain writable',
    () {
      final targets = findFillTargets(
        _doc([
          const TextBlock('성명: 홍길동', Box(20, 20, 300, 20)),
          const TextBlock('주소: 서울시 가상로 1', Box(20, 70, 300, 20)),
          const TextBlock('성명: ______', Box(20, 120, 300, 20)),
        ]),
      );
      expect(targets.map((t) => t.label), ['성명']);
      expect(targets.single.rect.y, greaterThan(100));
    },
  );

  test('duplicate names are numbered per page and respect each page size', () {
    final sizes = [const PageSize(1000, 1400), const PageSize(300, 200)];
    final targets = findFillTargets(
      _doc([
        const TextBlock('성명:', Box(10, 20, 100, 20)),
        const TextBlock('성명:', Box(10, 80, 100, 20)),
        const TextBlock('성명:', Box(10, 20, 100, 20), 1),
      ], pages: sizes),
    );
    expect(targets.map((t) => t.label), ['1페이지 성명', '1페이지 둘째 성명', '2페이지 성명']);
    expect(targets.map((t) => t.id).toSet(), hasLength(3));
    for (final t in targets) {
      _expectOnPage(t.rect, sizes[t.page]);
    }
  });

  test('signature targets stay inside all four page edges', () {
    const size = PageSize(300, 400);
    for (final box in [
      const Box(0, 0, 40, 20),
      const Box(260, 0, 40, 20),
      const Box(0, 380, 40, 20),
      const Box(260, 380, 40, 20),
    ]) {
      final target = findFillTargets(
        _doc([TextBlock('(서명)', box)], pages: [size]),
      ).single;
      _expectOnPage(target.rect, size);
    }
  });

  test(
    'large signature on a cropped photo does not extend beyond the image',
    () {
      const size = PageSize(200, 120);
      final target = findFillTargets(
        _doc([const TextBlock('(서명)', Box(10, 20, 180, 80))], pages: [size]),
      ).single;
      _expectOnPage(target.rect, size);
    },
  );

  test(
    'malformed page references and zero-area OCR are ignored without losing valid fields',
    () {
      final targets = findFillTargets(
        _doc(
          [
            const TextBlock('서명', Box(20, 20, 100, 20), -1),
            const TextBlock('서명', Box(20, 20, 100, 20), 3),
            const TextBlock('서명', Box(20, 20, 100, 0)),
            const TextBlock('서명', Box(20, 20, 0, 20)),
            const TextBlock('서명', Box(20, 20, 100, -20)),
            const TextBlock('서명', Box(20, 20, -100, 20)),
            const TextBlock('서명', Box(300, 20, 100, 20)),
            const TextBlock('서명', Box(-120, 20, 100, 20)),
            const TextBlock('서명', Box(20, 20, 100, 20), 1),
            const TextBlock('성명:', Box(20, 80, 100, 20)),
          ],
          pages: [const PageSize(300, 400), const PageSize(0, 400)],
        ),
      );
      expect(targets.map((t) => t.label), ['1페이지 성명']);
    },
  );

  test(
    'checkbox selections at the photo edge fit inside the exported ink canvas',
    () {
      const size = PageSize(180, 100);
      const block = TextBlock('□예 □아니요', Box(0, 0, 160, 20));
      final target = findFillTargets(_doc([block], pages: [size])).single;
      final boxes = checkBoxRects(target, block)!;
      final span = _rect(target.rect);
      expect(boxes.yes.width, greaterThan(0));
      expect(boxes.no.width, greaterThan(0));
      expect(boxes.yes.center.dx, lessThan(boxes.no.center.dx));
      expect(span.intersect(boxes.yes), boxes.yes);
      expect(span.intersect(boxes.no), boxes.no);
      _expectOnPage(target.rect, size);
    },
  );

  test('checkbox lookup and consent owner never leak across pages', () {
    final document = _doc(
      [
        const TextBlock('보호자 개인정보 수집 및 이용 동의', Box(20, 20, 250, 20)),
        const TextBlock('□예 □아니요', Box(20, 70, 200, 20)),
        const TextBlock('□예 □아니요', Box(20, 70, 200, 20), 1),
      ],
      pages: [const PageSize(300, 400), const PageSize(300, 400)],
    );
    final targets = findFillTargets(document);
    expect(targets, hasLength(2));
    expect(targets.first.label, contains('보호자'));
    expect(targets.last.label, isNot(contains('보호자')));
    expect(findCheckBlock(targets.last, document.blocks)!.page, 1);
  });

  test(
    'date blanks request only missing parts and exclude a completed date',
    () {
      final targets = findFillTargets(
        _doc([
          const TextBlock('년  월  일', Box(100, 30, 180, 20)),
          const TextBlock('2026년  월  일', Box(100, 90, 180, 20)),
          const TextBlock('2026년 11월 9일', Box(100, 150, 180, 20)),
        ]),
      );
      expect(targets.map((t) => t.datePart), ['연도', '월', '일', '월', '일']);
    },
  );

  test(
    'a field label at the right edge does not create space over printed text',
    () {
      final targets = findFillTargets(
        _doc(
          [const TextBlock('성명:', Box(250, 20, 50, 20))],
          pages: [const PageSize(300, 400)],
        ),
      );
      expect(targets, isEmpty);
    },
  );

  test(
    'a cropped-photo signature remains wholly visible in the actual PDF',
    () async {
      final document = _doc(
        [const TextBlock('(서명)', Box(10, 20, 180, 80))],
        pages: [const PageSize(200, 120)],
      );
      final target = findFillTargets(document).single;
      final pdf = await buildSignedPdf(
        pages: [await _photo(200, 120)],
        document: document,
        signatures: const {},
        fills: [FilledInk(target: target, png: await _png(80, 20))],
      );
      final images = _pdfImages(pdf);
      expect(images, hasLength(2));
      final ink = images.last;
      final width = PdfPageFormat.a4.width;
      final height = width * 120 / 200;
      expect(ink[4], greaterThanOrEqualTo(0));
      expect(ink[5], greaterThanOrEqualTo(0));
      expect(ink[4] + ink[0], lessThanOrEqualTo(width + 0.001));
      expect(ink[5] + ink[3], lessThanOrEqualTo(height + 0.001));
    },
  );
  test(
    'unfilled documents export exactly their photos in original page order',
    () async {
      final pdf = await buildSignedPdf(
        pages: [await _photo(100, 150), await _photo(120, 80)],
        document: _doc(
          [],
          pages: [const PageSize(1000, 1500), const PageSize(1200, 800)],
        ),
        signatures: const {},
      );
      final images = _pdfImages(pdf);
      expect(images, hasLength(2));
      expect(images[0][3], closeTo(PdfPageFormat.a4.width * 1.5, 0.001));
      expect(images[1][3], closeTo(PdfPageFormat.a4.width * 2 / 3, 0.001));
    },
  );

  test(
    'corrupt photo bytes fail export rather than producing a signed-looking PDF',
    () async {
      await expectLater(
        buildSignedPdf(
          pages: [
            DocumentPhoto(
              bytes: Uint8List.fromList([1, 2, 3]),
              name: 'broken.png',
            ),
          ],
          document: _doc([]),
          signatures: const {},
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'legacy image dimensions keep fill geometry when pages metadata is absent',
    () async {
      final pdf = await buildSignedPdf(
        pages: [await _photo(100, 150)],
        document: _doc([], pages: const [], width: 1000, height: 1500),
        signatures: const {},
        fills: [
          FilledInk(
            target: const FillTarget(
              id: 'legacy',
              label: '서명',
              page: 0,
              rect: Box(100, 200, 200, 100),
              isSignature: true,
            ),
            png: await _png(40, 20),
          ),
        ],
      );
      final images = _pdfImages(pdf);
      expect(images, hasLength(2));
      final scale = PdfPageFormat.a4.width / 1000;
      expect(images.last[0], closeTo(200 * scale, 0.001));
      expect(images.last[3], closeTo(100 * scale, 0.001));
      expect(images.last[4], closeTo(100 * scale, 0.001));
      expect(images.last[5], closeTo(1200 * scale, 0.001));
    },
  );

  test(
    'EXIF quarter turns preserve photo orientation and upright OCR coordinates',
    () async {
      for (final orientation in [6, 8]) {
        final pdf = await buildSignedPdf(
          pages: [
            DocumentPhoto(
              bytes: base64Decode(_cameraJpeg[orientation]!),
              name: 'camera.jpg',
            ),
          ],
          document: _doc([], pages: [const PageSize(40, 80)]),
          signatures: const {},
          fills: [
            FilledInk(
              target: const FillTarget(
                id: 'upright',
                label: '서명',
                page: 0,
                rect: Box(10, 20, 20, 10),
                isSignature: true,
              ),
              png: await _png(40, 20),
            ),
          ],
        );
        final images = _pdfImages(pdf);
        expect(images, hasLength(2));
        final width = PdfPageFormat.a4.width;
        expect(images.first[0], closeTo(0, 0.001));
        expect(images.first[3], closeTo(0, 0.001));
        expect(
          images.first[1],
          closeTo(orientation == 6 ? -width * 2 : width * 2, 0.001),
        );
        expect(
          images.first[2],
          closeTo(orientation == 6 ? width : -width, 0.001),
        );
        expect(images.last[4], closeTo(width / 4, 0.001));
        expect(images.last[5], closeTo(width * 1.25, 0.001));
      }
    },
  );
}

RecognizedDocument _doc(
  List<TextBlock> blocks, {
  List<PageSize> pages = const [PageSize(1000, 1400)],
  int width = 1000,
  int height = 1400,
}) => RecognizedDocument(
  docType: 'application',
  docTypeLabel: '신청서',
  blocks: blocks,
  fields: const [],
  fullText: '',
  imageWidth: width,
  imageHeight: height,
  pages: pages,
  reader: 'rules',
  speech: '',
);

ui.Rect _rect(Box b) => ui.Rect.fromLTWH(
  b.x.toDouble(),
  b.y.toDouble(),
  b.width.toDouble(),
  b.height.toDouble(),
);

void _expectOnPage(Box b, PageSize size) {
  expect(b.width, greaterThan(0));
  expect(b.height, greaterThan(0));
  expect(b.x, greaterThanOrEqualTo(0));
  expect(b.y, greaterThanOrEqualTo(0));
  expect(b.x + b.width, lessThanOrEqualTo(size.width));
  expect(b.y + b.height, lessThanOrEqualTo(size.height));
}

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

Future<DocumentPhoto> _photo(int width, int height) async =>
    DocumentPhoto(bytes: await _png(width, height), name: 'synthetic.png');

// Recover image transforms from the generated PDF, including nested translations.
List<List<double>> _pdfImages(Uint8List pdf) {
  final images = <List<double>>[];
  final streams = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
  final ops = RegExp(
    r'\b(q|Q)\b|([-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+ [-\d.]+) cm|/\S+ Do',
  );
  for (final stream in streams.allMatches(latin1.decode(pdf))) {
    final raw = latin1.encode(stream.group(1)!);
    String commands;
    try {
      commands = latin1.decode(zlib.decode(raw));
    } on FormatException {
      commands = latin1.decode(raw);
    }
    if (!commands.contains(' Do ')) continue;
    var matrix = <double>[1, 0, 0, 1, 0, 0];
    final saved = <List<double>>[];
    for (final op in ops.allMatches(commands)) {
      if (op.group(1) == 'q') {
        saved.add(matrix);
      } else if (op.group(1) == 'Q') {
        matrix = saved.removeLast();
      } else if (op.group(2) case final transform?) {
        final n = transform.split(' ').map(double.parse).toList(), m = matrix;
        matrix = [
          m[0] * n[0] + m[2] * n[1],
          m[1] * n[0] + m[3] * n[1],
          m[0] * n[2] + m[2] * n[3],
          m[1] * n[2] + m[3] * n[3],
          m[0] * n[4] + m[2] * n[5] + m[4],
          m[1] * n[4] + m[3] * n[5] + m[5],
        ];
      } else {
        images.add(matrix);
      }
    }
  }
  expect(images, isNotEmpty);
  return images;
}

// Synthetic 80 x 40 white JPEGs, with EXIF orientations 6 and 8.
const _cameraJpeg = <int, String>{
  6:
      '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBD'
      'ABsSFBcUERsXFhceHBsgKEIrKCUlKFE6PTBCYFVlZF9VXVtqeJmBanGQc1tdhbWGkJ6jq62rZ4C8ybqm'
      'x5moq6T/2wBDARweHigjKE4rK06kbl1upKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSk'
      'pKSkpKSkpKSkpKSkpKT/wAARCAAoAFADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQF'
      'BgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAk'
      'M2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
      'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
      '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQA'
      'AQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5'
      'OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmq'
      'srO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDp'
      'qKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA'
      '/9k=',
  8:
      '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAgAAAAAAAD/2wBD'
      'ABsSFBcUERsXFhceHBsgKEIrKCUlKFE6PTBCYFVlZF9VXVtqeJmBanGQc1tdhbWGkJ6jq62rZ4C8ybqm'
      'x5moq6T/2wBDARweHigjKE4rK06kbl1upKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSkpKSk'
      'pKSkpKSkpKSkpKSkpKT/wAARCAAoAFADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQF'
      'BgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAk'
      'M2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
      'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
      '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQA'
      'AQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5'
      'OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmq'
      'srO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDp'
      'qKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA'
      '/9k=',
};

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/document_photo.dart';
import '../../models/fill.dart';
import '../../models/recognized_document.dart';
import '../fill/fill_targets.dart';

/// 패드 서명 안내 상자의 가로세로 비율. 서명 PNG도 이 비율로 그려진다
const _signatureAspect = 2.6;

/// 서명 높이 = 줄 높이 × 이 값. 서명은 보통 글자보다 크게 써서 줄보다 넉넉히 잡는다
const _signatureLineScale = 2.2;

final _keyword = RegExp(r'서명|\(인\)|날인');

/// 페이지 사진마다 PDF 한 쪽. 서명란 줄(signatures의 key)에 서명 PNG를 겹쳐 그린다.
/// [notes](페이지 번호 → 노트 PNG)가 있으면 그 페이지 전체에 먼저 겹친다. 서명이 쓴 글씨에 가리지 않게 서명은 그 위에.
///
/// [fills](쓰고 서명하기에서 채운 칸)는 맨 위에 칸 자리마다 그린다.
///
/// 종이를 다시 출력하지 않고 찍은 사진 위에 그리므로, 사용자가 들은 문서와 서명된 문서가 같다.
Future<Uint8List> buildSignedPdf({
  required List<DocumentPhoto> pages,
  required RecognizedDocument document,
  required Map<int, Uint8List> signatures,
  Map<int, Uint8List> notes = const {},
  List<FilledInk> fills = const [],
}) async {
  final pdf = pw.Document();
  for (final (i, photo) in pages.indexed) {
    final size = _pageSize(document, i);
    // 크기를 모르면 사진을 디코딩해서 재지 않고 A4에 맞춰 넣기만 한다 (서명 위치를 계산할 수 없다)
    final format = size == null
        ? PdfPageFormat.a4
        : PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.width * size.height / size.width);
    final scale = size == null ? 0.0 : format.width / size.width;

    // 노트는 페이지 사진과 같은 픽셀 크기의 투명 PNG라, 사진과 똑같이 깔면 제자리에 겹친다
    final note = notes[i];
    final overlays = <pw.Widget>[
      if (note != null)
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Image(
            pw.MemoryImage(note),
            width: format.width,
            height: format.height,
            fit: size == null ? pw.BoxFit.contain : pw.BoxFit.fill,
          ),
        ),
      if (size != null)
        for (final MapEntry(key: line, value: png) in signatures.entries)
          if (line >= 0 && line < document.blocks.length && document.blocks[line].page == i)
            _placeSignature(document.blocks[line], png, scale, format),
      if (size != null)
        for (final fill in fills)
          if (fill.target.page == i) _placeFill(fill, scale),
    ];

    pdf.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Image(
            pw.MemoryImage(photo.bytes),
            width: format.width,
            height: format.height,
            fit: size == null ? pw.BoxFit.contain : pw.BoxFit.fill,
          ),
        ),
        ...overlays,
      ]),
    ));
  }
  return pdf.save();
}

/// 예전 단일 페이지 결과에는 pages가 없을 수 있어 image 크기로 대신한다
PageSize? _pageSize(RecognizedDocument document, int page) {
  if (page < document.pages.length) return document.pages[page];
  if (page == 0 && document.imageWidth > 0 && document.imageHeight > 0) {
    return PageSize(document.imageWidth, document.imageHeight);
  }
  return null;
}

/// OCR은 줄 단위 상자만 주므로, 키워드가 줄 글자 중 어디쯤인지 비율로 x를 어림한다
pw.Widget _placeSignature(TextBlock block, Uint8List png, double scale, PdfPageFormat format) {
  final box = block.box;
  final height = box.height * _signatureLineScale * scale;
  final width = height * _signatureAspect;

  // OCR 띄어쓰기는 믿기 어려워("서 명") 공백을 지우고 찾는다
  final compact = block.text.replaceAll(RegExp(r'\s+'), '');
  final match = _keyword.firstMatch(compact);
  final double left;
  if (match != null && compact.isNotEmpty) {
    // 키워드 가운데에 서명 가운데를 맞춘다. "(인)"의 괄호 시작점에 맞추면 앞 글자를 덮는다
    final ratio = (match.start + (match.end - match.start) / 2) / compact.length;
    left = (box.x + ratio * box.width) * scale - width / 2;
  } else {
    left = (box.x + box.width) * scale - width;
  }
  final top = (box.y + box.height / 2) * scale - height / 2;

  return pw.Positioned(
    left: _clamp(left, format.width - width),
    top: _clamp(top, format.height - height),
    child: pw.Image(pw.MemoryImage(png), width: width, height: height, fit: pw.BoxFit.contain),
  );
}

/// 서명이 페이지보다 크면 0에 붙인다
double _clamp(double value, double max) => value.clamp(0.0, math.max(0.0, max));

/// "1페이지 근로자 줄, 2페이지 사업주 줄에 서명을 넣었어요. PDF를 내려받았어요." (들려줄 말)
/// [notes]가 있으면 쓴 글씨도 넣었다고 앞에 알린다
String describeSignedPdf(
  RecognizedDocument document,
  Map<int, Uint8List> signatures, {
  Map<int, Uint8List> notes = const {},
}) {
  final noted = notes.keys.toList()..sort();
  final notePart = noted.isEmpty ? '' : '${noted.map((p) => '${p + 1}페이지').join(', ')}에 쓴 글씨를 넣었어요. ';
  if (signatures.isEmpty) return '$notePart넣은 서명이 없어요. 서명 없이 PDF를 내려받았어요.';
  final multiPage = document.pages.length > 1;
  final lines = signatures.keys.toList()..sort();
  final parts = [
    for (final line in lines)
      if (line >= 0 && line < document.blocks.length)
        multiPage
            ? '${document.blocks[line].page + 1}페이지 ${_lineName(document.blocks[line].text, line)}'
            : _lineName(document.blocks[line].text, line)
      else
        '${line + 1}번째 줄',
  ];
  return '$notePart${parts.join(', ')}에 서명을 넣었어요. PDF를 내려받았어요.';
}

/// 서명 탭과 같은 방식으로 줄 맨 앞의 주체(근로자, 사업주…)로 부른다.
/// 서명 탭 코드는 다른 사람이 바꾸는 중이라 기대지 않고 여기서 따로 계산한다
String _lineName(String text, int line) {
  // OCR 띄어쓰기는 믿기 어려워("사업 주") 공백을 지우고, 첫 칸 이름(상호, 주소, 성명…) 앞까지를 쓴다
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  final owner = RegExp(r'^([가-힣]{1,6}?)(상호|주소|성명|대표자?|이름|연락처|[:：(]|서명)').firstMatch(compact)?.group(1);
  final generic = owner == null || RegExp(r'^(성명|이름|주소|상호|대표자?|연락처)$').hasMatch(owner);
  return generic ? '${line + 1}번째 줄' : '$owner 줄';
}

/// 채운 칸 하나. 글씨 PNG는 획만 잘라낸 것이라 칸 상자에 비율을 지켜 넣는다.
/// 글씨 칸은 쓰는 자리처럼 왼쪽에 붙이고, 서명은 가운데에 둔다
/// (화면의 넣기 움직임과 같은 자리: 글씨 칸은 칸 높이의 15%만큼 안쪽에서 시작한다)
pw.Widget _placeFill(FilledInk fill, double scale) {
  final b = fill.target.rect;
  final rect = fill.target.isSignature
      ? Rect.fromLTWH(b.x.toDouble(), b.y.toDouble(), b.width.toDouble(), b.height.toDouble())
      : fillTextInset(Rect.fromLTWH(b.x.toDouble(), b.y.toDouble(), b.width.toDouble(), b.height.toDouble()));
  return pw.Positioned(
    left: rect.left * scale,
    top: rect.top * scale,
    child: pw.Image(
      pw.MemoryImage(fill.png),
      width: rect.width * scale,
      height: rect.height * scale,
      fit: pw.BoxFit.contain,
      alignment: fill.target.isSignature ? pw.Alignment.center : pw.Alignment.centerLeft,
    ),
  );
}

/// "1페이지 학생 성명, 보호자 서명을 채웠어요. PDF를 내려받았어요." (들려줄 말)
/// 페이지가 하나면 페이지 번호는 말하지 않는다
String describeFills(List<FilledInk> fills, int pageCount) {
  if (fills.isEmpty) return '채운 칸이 없어요. 글씨 없이 PDF를 내려받았어요.';
  final byPage = <int, List<String>>{};
  for (final fill in fills) {
    // 여러 페이지 문서의 칸 이름에는 "2페이지 "가 붙어 있어 페이지별로 묶을 때는 뗀다
    final name = fill.target.label.replaceFirst(RegExp(r'^\d+페이지 '), '');
    byPage.putIfAbsent(fill.target.page, () => []).add(name);
  }
  final pages = byPage.keys.toList()..sort();
  final joined = [
    for (final p in pages) pageCount > 1 ? '${p + 1}페이지 ${byPage[p]!.join(', ')}' : byPage[p]!.join(', '),
  ].join(', ');
  return '${_eulReul(joined)} 채웠어요. PDF를 내려받았어요.';
}

/// 받침이 있으면 "을", 없으면 "를"
String _eulReul(String word) {
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return '$word을';
  return (code - 0xAC00) % 28 == 0 ? '$word를' : '$word을';
}
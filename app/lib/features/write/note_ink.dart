import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/recognized_document.dart';

/// 노트에 쓴 획 하나. 좌표와 굵기는 모두 페이지 사진 픽셀 단위다.
///
/// 화면 좌표로 두면 창 크기가 바뀔 때마다 어긋나고, 저장한 PNG가 사진과 겹치지 않는다.
class NoteStroke {
  NoteStroke(this.unit);

  /// 쓸 때 화면 1픽셀이 사진 몇 픽셀이었는지. 화면에서 보던 굵기를 사진에서도 그대로 지키려고 둔다
  final double unit;

  final List<Offset> points = [];
  final List<double> pressures = [];

  void add(Offset point, double pressure) {
    points.add(point);
    pressures.add(pressure);
  }

  /// 필압을 모르는 기기(마우스 일부)는 0을 주므로 중간값으로 본다
  double widthAt(int i) {
    final pressure = pressures[i] <= 0 ? 0.5 : pressures[i].clamp(0.0, 1.0);
    return (2.5 + pressure * 5) * unit;
  }
}

/// 노트 잉크를 그리고, PNG로 만들고, 페이지 사진과 합친다.
/// 화면(노트 패드)과 저장(PNG), 확인(합성) 모두 같은 함수로 그려서 보이는 대로 저장되게 한다.
class NoteInk {
  NoteInk._();

  /// 짙은 파랑. 검은 인쇄 글자와 구별되고 저시력 사용자에게도 대비가 높다
  static const color = Color(0xFF1A2A80);

  /// 합성 사진의 긴 변 최대 길이. 폰 사진 원본을 PNG로 올리면 수십 MB가 되어 느리다
  static const maxCompositeSide = 2400;

  /// 페이지 사진 크기. 예전 단일 페이지 결과에는 pages가 없을 수 있어 image 크기로 대신한다
  static PageSize? pageSize(RecognizedDocument? document, int page) {
    if (document == null) return null;
    if (page < document.pages.length) return document.pages[page];
    if (page == 0 && document.imageWidth > 0 && document.imageHeight > 0) {
      return PageSize(document.imageWidth, document.imageHeight);
    }
    return null;
  }

  /// 페이지 좌표의 획을 그린다. 호출하는 쪽이 캔버스를 페이지 좌표로 맞춰 둔다
  static void paintStrokes(Canvas canvas, List<NoteStroke> strokes) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      // 콕 찍은 점(받침의 점, 마침표)도 보이게 한다
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.widthAt(0) / 2, paint);
        continue;
      }
      for (var i = 1; i < stroke.points.length; i++) {
        canvas.drawLine(stroke.points[i - 1], stroke.points[i], paint..strokeWidth = stroke.widthAt(i));
      }
    }
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// 잉크만 담은 투명 배경 PNG. 페이지 사진과 같은 픽셀 크기라 그대로 겹치면 맞는다.
  /// [base]는 전에 저장한 노트 (이어 쓰기)
  static Future<Uint8List> toPng({
    required int width,
    required int height,
    required List<NoteStroke> strokes,
    ui.Image? base,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final page = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    if (base != null) _drawImage(canvas, base, page);
    paintStrokes(canvas, strokes);
    return _encode(recorder, width, height);
  }

  /// 페이지 사진 위에 노트 잉크를 얹은 한 장의 PNG. 쓰기 확인 API에 사진 대신 보낸다.
  /// [size]는 읽기 결과의 페이지 크기 (노트는 이 크기로 저장된다). 모르면 사진 크기를 쓴다
  static Future<Uint8List> composite({
    required Uint8List photo,
    Uint8List? note,
    PageSize? size,
    int maxSide = maxCompositeSide,
  }) async {
    final image = await decode(photo);
    final ink = note == null ? null : await decode(note);
    final pageWidth = size?.width ?? image.width;
    final pageHeight = size?.height ?? image.height;
    final scale = math.min(1.0, maxSide / math.max(pageWidth, pageHeight));
    final width = math.max(1, (pageWidth * scale).round());
    final height = math.max(1, (pageHeight * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    // 손글씨 확인용이라 배경을 흰색으로 깐다 (투명한 곳이 검게 보이는 뷰어가 있다)
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    _drawImage(canvas, image, rect);
    if (ink != null) _drawImage(canvas, ink, rect);
    image.dispose();
    ink?.dispose();
    return _encode(recorder, width, height);
  }

  /// 노트와 사진은 같은 페이지 좌표를 쓰므로 둘 다 페이지 상자에 꽉 채워 그린다
  static void _drawImage(Canvas canvas, ui.Image image, Rect rect) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static Future<Uint8List> _encode(ui.PictureRecorder recorder, int width, int height) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

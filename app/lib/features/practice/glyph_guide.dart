import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hangul.dart';
import 'stroke_metrics.dart';

/// 글꼴로 보조선 지도를 만든다. 글자마다 획 경로를 손으로 그려 넣지 않고,
/// 목표 글자를 앱에 내장된 도현체로 그려 낮은 해상도 격자(긴 변 128칸)에 찍은 뒤 거리 지도를 계산한다.
/// 그래서 사용자 이름처럼 아무 낱말이나 연습할 수 있다.
class GlyphGuide {
  GlyphGuide._();

  /// 보조 글자 전용 글꼴 이름. 화면에 쓰는 도현체와 같은 파일을 직접 불러 항상 준비된 상태로 쓴다
  static const _family = 'GuideGlyph';
  static const _fontAsset = 'assets/fonts/DoHyeon-Regular.ttf';
  static String _loadedFamily = 'DoHyeon';
  static Future<void>? _fontReady;

  static Future<void> ensureFont() => _fontReady ??= _loadFont();

  static Future<void> _loadFont() async {
    try {
      final loader = FontLoader(_family)..addFont(rootBundle.load(_fontAsset));
      await loader.load();
      _loadedFamily = _family;
    } catch (_) {
      // 불러오지 못하면 테마에 등록된 도현체로 그린다
    }
  }

  /// 쓰기 칸 [area]에 맞는 글자 크기. 글자 하나는 칸 가운데에 크게, 낱말은 한 줄로
  static double fontSizeFor(String text, Size area) {
    final n = math.max(1, text.runes.length);
    if (n == 1) return math.min(area.width * 0.78, area.height * 0.7);
    return math.min(area.height * 0.55, area.width * 0.92 / n);
  }

  static TextPainter _painter(String text, double fontSize, Color color) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: _loadedFamily, fontSize: fontSize, color: color, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static Offset _origin(TextPainter painter, Size area) =>
      Offset((area.width - painter.width) / 2, (area.height - painter.height) / 2);

  /// 보조 글자를 화면에 그린다. 지도를 만들 때와 같은 글꼴·위치라서 정확히 겹친다
  static void paint(Canvas canvas, Size area, String text, double fontSize, Color color) {
    final painter = _painter(text, fontSize, color);
    painter.paint(canvas, _origin(painter, area));
  }

  /// [text]를 [area] 크기 쓰기 칸 가운데에 [fontSize]로 그린 것의 거리 지도
  static Future<GuideMap> build({required String text, required Size area, required double fontSize}) async {
    await ensureFont();
    final painter = _painter(text, fontSize, const Color(0xFF000000));
    final origin = _origin(painter, area);

    final cell = math.max(area.width, area.height) / 128;
    final cols = (area.width / cell).ceil();
    final rows = (area.height / cell).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(1 / cell);
    painter.paint(canvas, origin);
    final picture = recorder.endRecording();
    final image = await picture.toImage(cols, rows);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();

    final ink = Uint8List(cols * rows);
    if (bytes != null) {
      for (var i = 0; i < ink.length; i++) {
        ink[i] = bytes.getUint8(i * 4 + 3) > 80 ? 1 : 0;
      }
    }

    final base = GuideMap.fromMask(ink: ink, cols: cols, rows: rows, cell: cell, glyphSize: fontSize);
    return base.withUnits(_units(base, painter, origin, area, text));
  }

  /// 글자마다 상자(가로 범위)와 실제 글씨 범위, 초·중·종성 부분 칸을 구한다
  static List<GuideUnit> _units(GuideMap map, TextPainter painter, Offset origin, Size area, String text) {
    final units = <GuideUnit>[];
    final chars = text.split('');
    for (var i = 0; i < chars.length; i++) {
      final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (boxes.isEmpty) continue;
      final box = Rect.fromLTRB(origin.dx + boxes.first.left, 0, origin.dx + boxes.first.right, area.height);
      final ink = map.inkBoundsIn(box);
      if (ink.isEmpty) continue;
      final parts = [
        for (final part in syllableParts(chars[i]))
          GuidePart(
            part.name,
            Rect.fromLTRB(
              ink.left + part.unit.left * ink.width,
              ink.top + part.unit.top * ink.height,
              ink.left + part.unit.right * ink.width,
              ink.top + part.unit.bottom * ink.height,
            ),
          ),
      ];
      units.add(GuideUnit(text: chars[i], box: box, ink: ink, parts: parts));
    }
    return units;
  }
}

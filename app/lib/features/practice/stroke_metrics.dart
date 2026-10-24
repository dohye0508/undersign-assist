import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// 글씨를 숫자로만 잰다 (AI 안 씀). 보조 글자를 글꼴로 그려 만든 "거리 지도"를 기준으로 삼는다.
/// 화면과 글꼴에 매이지 않는 순수 계산이라 단위 시험이 된다.

/// 판정 기준값. 처음 값이며 팀원이 실제 태블릿에서 써 보고 조정한다
class Thresholds {
  Thresholds._();

  /// 보조 글자 크기 대비 허용 거리 (펜이 글자에서 이만큼 안에 있으면 "안쪽")
  static const tolerance = 0.08;

  static const minInside = 0.70;
  static const minCovered = 0.60;
  static const minSize = 0.6;
  static const maxSize = 1.5;

  /// 펜 가운데와 보조 글자 가운데의 차이 (보조 글자의 긴 변 대비)
  static const maxOffset = 0.25;
  static const maxTiltDegrees = 8.0;
  static const minSpacing = 0.05;
  static const maxSpacing = 0.8;

  /// 이 칸 수보다 작은 부분은 판정에서 뺀다 (가는 획 하나뿐인 부분 등)
  static const minPartCells = 8;
}

/// 음절 안의 한 부분 (초성·중성·종성) 칸. 캔버스 좌표
class GuidePart {
  const GuidePart(this.name, this.rect);

  final String name;
  final Rect rect;
}

/// 보조선의 글자 하나. 낱말이면 음절마다 하나
class GuideUnit {
  const GuideUnit({required this.text, required this.box, required this.ink, this.parts = const []});

  final String text;

  /// 글자 상자 (캔버스 좌표). 이 음절에 속하는 가로 범위
  final Rect box;

  /// 상자 안에서 글씨가 실제로 차지한 범위
  final Rect ink;
  final List<GuidePart> parts;
}

/// 보조 글자의 거리 지도. 낮은 해상도 격자 하나에 "글자 칸"을 표시하고,
/// 각 칸에서 가장 가까운 글자 칸까지의 거리를 한 번 계산해 둔다. 이후 계산은 이 지도만 본다
class GuideMap {
  GuideMap._({
    required this.cols,
    required this.rows,
    required this.cell,
    required this.origin,
    required this.ink,
    required this.distance,
    required this.glyphSize,
    required this.inkBounds,
    required this.units,
  });

  /// [ink]는 칸마다 0 또는 1 (글자 칸이면 1). [cell]은 칸 하나의 변 길이(캔버스 픽셀),
  /// [origin]은 첫 칸의 왼쪽 위 모서리, [glyphSize]는 보조 글자 크기(허용 거리의 기준)
  factory GuideMap.fromMask({
    required Uint8List ink,
    required int cols,
    required int rows,
    required double cell,
    required double glyphSize,
    Offset origin = Offset.zero,
    List<GuideUnit> units = const [],
  }) {
    assert(ink.length == cols * rows);
    var minX = cols, minY = rows, maxX = -1, maxY = -1;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (ink[y * cols + x] == 0) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    final bounds = maxX < 0
        ? Rect.zero
        : Rect.fromLTRB(
            origin.dx + minX * cell,
            origin.dy + minY * cell,
            origin.dx + (maxX + 1) * cell,
            origin.dy + (maxY + 1) * cell,
          );
    return GuideMap._(
      cols: cols,
      rows: rows,
      cell: cell,
      origin: origin,
      ink: ink,
      distance: distanceCells(ink, cols, rows),
      glyphSize: glyphSize,
      inkBounds: bounds,
      units: units.isEmpty ? [GuideUnit(text: '', box: bounds, ink: bounds)] : units,
    );
  }

  /// 시험·미리보기용: 글자 모양을 ASCII 그림으로 준다 ('#'이 글자 칸)
  factory GuideMap.fromAscii(List<String> rowsText, {double cell = 4, double? glyphSize}) {
    final rows = rowsText.length;
    final cols = rowsText.first.length;
    final ink = Uint8List(cols * rows);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (rowsText[y][x] == '#') ink[y * cols + x] = 1;
      }
    }
    return GuideMap.fromMask(
      ink: ink,
      cols: cols,
      rows: rows,
      cell: cell,
      glyphSize: glyphSize ?? math.max(cols, rows) * cell,
    );
  }

  final int cols;
  final int rows;
  final double cell;
  final Offset origin;

  /// 칸마다 0 또는 1
  final Uint8List ink;

  /// 칸마다 가장 가까운 글자 칸까지의 거리 (칸 수 단위)
  final Float32List distance;
  final double glyphSize;

  /// 글자 칸 전체를 감싸는 상자 (캔버스 좌표)
  final Rect inkBounds;
  final List<GuideUnit> units;

  bool get isEmpty => inkBounds.isEmpty;

  /// 같은 지도에 글자 상자만 바꿔 붙인다 (거리 지도는 다시 계산하지 않는다)
  GuideMap withUnits(List<GuideUnit> newUnits) => GuideMap._(
        cols: cols,
        rows: rows,
        cell: cell,
        origin: origin,
        ink: ink,
        distance: distance,
        glyphSize: glyphSize,
        inkBounds: inkBounds,
        units: newUnits.isEmpty ? units : newUnits,
      );

  /// 캔버스 점 [p]에서 가장 가까운 글자 칸까지의 거리 (캔버스 픽셀). 격자 밖이면 가장자리까지의 거리를 더한다
  double distanceAt(Offset p) {
    final gx = (p.dx - origin.dx) / cell;
    final gy = (p.dy - origin.dy) / cell;
    final cx = gx.floor().clamp(0, cols - 1).toInt();
    final cy = gy.floor().clamp(0, rows - 1).toInt();
    final extraX = gx < 0 ? -gx : (gx > cols ? gx - cols : 0.0);
    final extraY = gy < 0 ? -gy : (gy > rows ? gy - rows : 0.0);
    final extra = math.sqrt(extraX * extraX + extraY * extraY);
    return (distance[cy * cols + cx] + extra) * cell;
  }

  /// 캔버스 점이 들어 있는 칸 (격자 밖이면 null)
  (int, int)? cellOf(Offset p) {
    final x = ((p.dx - origin.dx) / cell).floor();
    final y = ((p.dy - origin.dy) / cell).floor();
    if (x < 0 || y < 0 || x >= cols || y >= rows) return null;
    return (x, y);
  }

  Offset cellCenter(int x, int y) => Offset(origin.dx + (x + 0.5) * cell, origin.dy + (y + 0.5) * cell);

  /// [region] 안에 있는 글자 칸을 감싸는 상자 (없으면 [Rect.zero])
  Rect inkBoundsIn(Rect region) {
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (ink[y * cols + x] == 0) continue;
        final c = cellCenter(x, y);
        if (!region.contains(c)) continue;
        left = math.min(left, c.dx - cell / 2);
        right = math.max(right, c.dx + cell / 2);
        top = math.min(top, c.dy - cell / 2);
        bottom = math.max(bottom, c.dy + cell / 2);
      }
    }
    if (right < left) return Rect.zero;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// 칸마다 "가장 가까운 1 칸까지의 거리" (칸 수). 두 번 훑는 거리 변환(가로세로 1, 대각선 1.414)
  static Float32List distanceCells(Uint8List mask, int cols, int rows) {
    const big = 1.0e9;
    const diagonal = 1.4142;
    final d = Float32List(cols * rows);
    for (var i = 0; i < d.length; i++) {
      d[i] = mask[i] != 0 ? 0 : big;
    }
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final i = y * cols + x;
        var v = d[i];
        if (v == 0) continue;
        if (x > 0) v = math.min(v, d[i - 1] + 1);
        if (y > 0) {
          v = math.min(v, d[i - cols] + 1);
          if (x > 0) v = math.min(v, d[i - cols - 1] + diagonal);
          if (x < cols - 1) v = math.min(v, d[i - cols + 1] + diagonal);
        }
        d[i] = v;
      }
    }
    for (var y = rows - 1; y >= 0; y--) {
      for (var x = cols - 1; x >= 0; x--) {
        final i = y * cols + x;
        var v = d[i];
        if (v == 0) continue;
        if (x < cols - 1) v = math.min(v, d[i + 1] + 1);
        if (y < rows - 1) {
          v = math.min(v, d[i + cols] + 1);
          if (x < cols - 1) v = math.min(v, d[i + cols + 1] + diagonal);
          if (x > 0) v = math.min(v, d[i + cols - 1] + diagonal);
        }
        d[i] = v;
      }
    }
    return d;
  }
}

/// 한 번 쓴 글씨를 숫자로 요약한 것
class StrokeReport {
  const StrokeReport({
    required this.inside,
    required this.covered,
    required this.sizeRatio,
    required this.offsetX,
    required this.offsetY,
    this.tiltDegrees,
    this.spacingMin,
    this.spacingMax,
    this.worstPartName,
    this.worstPartCovered,
    this.worstPartUnit,
    this.uncoveredDirection,
  });

  /// 펜 점 중 보조 글자에서 허용 거리 안에 있는 점의 비율 (0~1)
  final double inside;

  /// 보조 글자 칸 중 펜이 허용 거리 안으로 지나간 칸의 비율 (0~1)
  final double covered;

  /// 펜 바깥 상자의 긴 변 ÷ 보조 글자의 긴 변
  final double sizeRatio;

  /// 펜 바깥 상자 가운데 − 보조 글자 가운데 (보조 글자의 긴 변 대비). x는 오른쪽이 +, y는 아래가 +
  final double offsetX;
  final double offsetY;

  /// 낱말: 음절 가운데를 이은 선의 기울기(도). 아래로 내려가면 +. 음절이 둘 미만이면 null
  final double? tiltDegrees;

  /// 낱말: 이웃 음절 사이 간격 ÷ 음절 너비의 가장 작은 값과 가장 큰 값
  final double? spacingMin;
  final double? spacingMax;

  /// 가장 덜 그려진 부분 (초성·중성·종성 이름, 그 비율, 속한 글자)
  final String? worstPartName;
  final double? worstPartCovered;
  final String? worstPartUnit;

  /// 부분 이름이 없을 때: 덜 그려진 쪽 ("왼쪽", "오른쪽", "위쪽", "아래쪽")
  final String? uncoveredDirection;

  static const empty = StrokeReport(inside: 0, covered: 0, sizeRatio: 0, offsetX: 0, offsetY: 0);
}

class StrokeMetrics {
  StrokeMetrics._();

  /// 획을 [step] 간격으로 촘촘히 채운 점들. 점 하나짜리 획은 그 점 그대로
  static List<Offset> resample(List<List<Offset>> strokes, double step) {
    final out = <Offset>[];
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      out.add(stroke.first);
      for (var i = 1; i < stroke.length; i++) {
        final a = stroke[i - 1];
        final b = stroke[i];
        final length = (b - a).distance;
        final n = (length / step).ceil();
        for (var k = 1; k <= n; k++) {
          out.add(Offset.lerp(a, b, k / n)!);
        }
      }
    }
    return out;
  }

  static StrokeReport measure(List<List<Offset>> strokes, GuideMap guide) {
    final points = resample(strokes, guide.cell);
    if (points.isEmpty || guide.isEmpty) return StrokeReport.empty;

    final tolerance = guide.glyphSize * Thresholds.tolerance;

    // 모양: 안쪽 비율
    var near = 0;
    for (final p in points) {
      if (guide.distanceAt(p) <= tolerance) near++;
    }
    final inside = near / points.length;

    // 모양: 덮은 비율. 펜이 지나간 칸을 표시하고 거리 변환을 한 번 더 한다
    final pen = Uint8List(guide.cols * guide.rows);
    for (final p in points) {
      final c = guide.cellOf(p);
      if (c != null) pen[c.$2 * guide.cols + c.$1] = 1;
    }
    final penDistance = GuideMap.distanceCells(pen, guide.cols, guide.rows);
    final toleranceCells = tolerance / guide.cell;

    var coveredCells = 0, inkCells = 0;
    var missX = 0.0, missY = 0.0, missCount = 0;
    final partCovered = <GuidePart, (int, int)>{};
    final parts = [for (final u in guide.units) ...u.parts];
    for (var y = 0; y < guide.rows; y++) {
      for (var x = 0; x < guide.cols; x++) {
        final i = y * guide.cols + x;
        if (guide.ink[i] == 0) continue;
        inkCells++;
        final hit = penDistance[i] <= toleranceCells;
        if (hit) {
          coveredCells++;
        } else {
          final c = guide.cellCenter(x, y);
          missX += c.dx;
          missY += c.dy;
          missCount++;
        }
        if (parts.isNotEmpty) {
          final c = guide.cellCenter(x, y);
          for (final part in parts) {
            if (!part.rect.contains(c)) continue;
            final old = partCovered[part] ?? (0, 0);
            partCovered[part] = (old.$1 + (hit ? 1 : 0), old.$2 + 1);
          }
        }
      }
    }
    final covered = inkCells == 0 ? 0.0 : coveredCells / inkCells;

    // 가장 덜 그려진 부분
    String? worstName, worstUnit;
    double? worstRatio;
    for (final unit in guide.units) {
      for (final part in unit.parts) {
        final stat = partCovered[part];
        if (stat == null || stat.$2 < Thresholds.minPartCells) continue;
        final ratio = stat.$1 / stat.$2;
        if (worstRatio == null || ratio < worstRatio) {
          worstRatio = ratio;
          worstName = part.name;
          worstUnit = unit.text;
        }
      }
    }

    // 덜 그려진 쪽 (부분 이름이 없는 자모·낱말용)
    String? direction;
    if (missCount > 0) {
      final cx = missX / missCount - guide.inkBounds.center.dx;
      final cy = missY / missCount - guide.inkBounds.center.dy;
      final nx = cx / math.max(guide.inkBounds.width, 1);
      final ny = cy / math.max(guide.inkBounds.height, 1);
      if (nx.abs() >= ny.abs()) {
        direction = nx < 0 ? '왼쪽' : '오른쪽';
      } else {
        direction = ny < 0 ? '위쪽' : '아래쪽';
      }
    }

    // 크기와 위치
    final penBounds = _bounds(points);
    final guideLongest = math.max(guide.inkBounds.longestSide, 1);
    final sizeRatio = penBounds.longestSide / guideLongest;
    final offsetX = (penBounds.center.dx - guide.inkBounds.center.dx) / guideLongest;
    final offsetY = (penBounds.center.dy - guide.inkBounds.center.dy) / guideLongest;

    // 낱말: 음절별로 갈라 기울기와 자간
    double? tilt, spacingMin, spacingMax;
    if (guide.units.length >= 2) {
      final perUnit = List<List<Offset>>.generate(guide.units.length, (_) => []);
      for (final p in points) {
        perUnit[_unitIndex(guide.units, p)].add(p);
      }
      final boxes = [for (final list in perUnit) list.length >= 2 ? _bounds(list) : null];

      final centers = [for (final b in boxes) if (b != null) b.center];
      if (centers.length >= 2) {
        final meanX = centers.map((c) => c.dx).reduce((a, b) => a + b) / centers.length;
        final meanY = centers.map((c) => c.dy).reduce((a, b) => a + b) / centers.length;
        var covariance = 0.0, variance = 0.0;
        for (final c in centers) {
          covariance += (c.dx - meanX) * (c.dy - meanY);
          variance += (c.dx - meanX) * (c.dx - meanX);
        }
        if (variance > 1e-6) tilt = math.atan(covariance / variance) * 180 / math.pi;
      }

      for (var i = 1; i < boxes.length; i++) {
        final a = boxes[i - 1], b = boxes[i];
        if (a == null || b == null) continue;
        final width = (a.width + b.width) / 2;
        if (width <= 0) continue;
        final ratio = (b.left - a.right) / width;
        spacingMin = spacingMin == null ? ratio : math.min(spacingMin, ratio);
        spacingMax = spacingMax == null ? ratio : math.max(spacingMax, ratio);
      }
    }

    return StrokeReport(
      inside: inside,
      covered: covered,
      sizeRatio: sizeRatio,
      offsetX: offsetX,
      offsetY: offsetY,
      tiltDegrees: tilt,
      spacingMin: spacingMin,
      spacingMax: spacingMax,
      worstPartName: worstName,
      worstPartCovered: worstRatio,
      worstPartUnit: worstUnit,
      uncoveredDirection: direction,
    );
  }

  static Rect _bounds(List<Offset> points) {
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (final p in points) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// 점이 어느 글자 상자에 속하는지 (안에 없으면 가로로 가장 가까운 상자)
  static int _unitIndex(List<GuideUnit> units, Offset p) {
    var best = 0;
    var bestGap = double.infinity;
    for (var i = 0; i < units.length; i++) {
      final box = units[i].box;
      final gap = p.dx < box.left ? box.left - p.dx : (p.dx > box.right ? p.dx - box.right : 0.0);
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return best;
  }
}

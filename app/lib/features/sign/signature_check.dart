import 'dart:math' as math;
import 'dart:ui';

/// 펜이 찍은 점 하나
class PenPoint {
  const PenPoint(this.position, this.timeMs, this.pressure);

  final Offset position;
  final int timeMs;

  /// 0~1. 마우스는 보통 0.5로 들어온다
  final double pressure;
}

/// 서명 한 번을 숫자로 요약한 것. 같은 세션에서 처음 통과한 서명을 기준값으로 쓴다
class SignatureMetrics {
  const SignatureMetrics({
    required this.strokeCount,
    required this.bounds,
    required this.areaRatio,
    required this.durationMs,
    required this.aspect,
    required this.outsideRatio,
  });

  final int strokeCount;
  final Rect bounds;

  /// 서명이 차지한 면적 ÷ 서명 칸 면적
  final double areaRatio;
  final int durationMs;

  /// 가로 ÷ 세로
  final double aspect;

  /// 칸 밖에 찍힌 점의 비율
  final double outsideRatio;

  factory SignatureMetrics.measure(List<List<PenPoint>> strokes, Rect guide) {
    final points = [for (final s in strokes) ...s];
    if (points.isEmpty) {
      return const SignatureMetrics(
        strokeCount: 0,
        bounds: Rect.zero,
        areaRatio: 0,
        durationMs: 0,
        aspect: 0,
        outsideRatio: 0,
      );
    }
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (final p in points) {
      left = math.min(left, p.position.dx);
      top = math.min(top, p.position.dy);
      right = math.max(right, p.position.dx);
      bottom = math.max(bottom, p.position.dy);
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom);
    final outside = points.where((p) => !guide.contains(p.position)).length;
    return SignatureMetrics(
      strokeCount: strokes.where((s) => s.isNotEmpty).length,
      bounds: bounds,
      areaRatio: (bounds.width * bounds.height) / (guide.width * guide.height),
      durationMs: points.last.timeMs - points.first.timeMs,
      aspect: bounds.height == 0 ? 0 : bounds.width / bounds.height,
      outsideRatio: outside / points.length,
    );
  }
}

/// 판정 결과. [ok]가 거짓이면 [message]로 다시 서명하라고 안내한다
class SignatureVerdict {
  const SignatureVerdict(this.ok, this.message, this.metrics);

  final bool ok;
  final String message;
  final SignatureMetrics metrics;
}

/// 서명을 수치로만 검사한다. AI가 "느낌"으로 판단하지 않는다 (계획서).
class SignatureCheck {
  SignatureCheck._();

  // 절대 기준 (기준값이 없을 때도 적용)
  static const minAreaRatio = 0.08;
  static const minDurationMs = 400;
  static const maxOutsideRatio = 0.05;

  // 기준값과 비교할 때
  static const minSizeVsBaseline = 0.5;

  /// 이 세션에서 처음 통과한 서명. 다음 서명은 이것과 비교한다
  static SignatureMetrics? baseline;

  static SignatureVerdict judge(List<List<PenPoint>> strokes, Rect guide) {
    final m = SignatureMetrics.measure(strokes, guide);
    final base = baseline;

    String? problem;
    if (m.strokeCount == 0) {
      problem = '아직 서명하지 않았어요. 칸 안에 서명해 주세요.';
    } else if (m.outsideRatio > maxOutsideRatio || !guide.inflate(2).contains(m.bounds.topLeft) ||
        !guide.inflate(2).contains(m.bounds.bottomRight)) {
      problem = '서명이 칸을 벗어났어요. 칸 안에 다시 서명해 주세요.';
    } else if (m.areaRatio < minAreaRatio) {
      problem = '서명이 너무 작아요. 칸을 더 크게 채워서 다시 서명해 주세요.';
    } else if (m.durationMs < minDurationMs) {
      problem = '너무 빨리 그었어요. 천천히 다시 서명해 주세요.';
    } else if (base != null && m.areaRatio < base.areaRatio * minSizeVsBaseline) {
      problem = '처음 서명보다 많이 작아요. 처음처럼 크게 다시 서명해 주세요.';
    } else if (base != null && (m.strokeCount - base.strokeCount).abs() > math.max(2, base.strokeCount ~/ 2)) {
      problem = '처음 서명과 획 수가 많이 달라요. 평소처럼 다시 서명해 주세요.';
    }

    if (problem != null) return SignatureVerdict(false, problem, m);
    return SignatureVerdict(true, '서명이 칸 안에 잘 들어왔어요.', m);
  }
}

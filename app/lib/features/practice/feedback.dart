import 'dart:math' as math;

import 'hangul.dart';
import 'stroke_metrics.dart';

/// 고칠 점의 종류
enum PracticeIssue { shape, missing, size, position, tilt, spacing }

/// 한 번 쓴 결과: 점수, 통과 여부, 말해 줄 고칠 점 한 가지
class PracticeVerdict {
  const PracticeVerdict({required this.score, required this.passed, required this.issue, required this.message});

  /// 0~100
  final int score;
  final bool passed;

  /// 가장 크게 벗어난 항목 (잘 썼으면 null)
  final PracticeIssue? issue;

  /// 음성으로 들려줄 문장. 잘 썼으면 칭찬
  final String message;
}

/// 숫자를 점수와 문장으로 바꾼다. 문장은 AI가 아니라 틀에 값을 넣어 코드가 만든다 (앱 원칙)
class PracticeJudge {
  PracticeJudge._();

  /// [label]은 쓴 글자나 낱말. [lenient]가 참이면 연습하기처럼 늘 통과로 본다
  static PracticeVerdict judge(StrokeReport r, {required String label, bool lenient = false}) {
    final deficits = <PracticeIssue, double>{};

    if (r.inside < Thresholds.minInside) {
      deficits[PracticeIssue.shape] = (Thresholds.minInside - r.inside) / Thresholds.minInside;
    }
    if (r.covered < Thresholds.minCovered) {
      deficits[PracticeIssue.missing] = (Thresholds.minCovered - r.covered) / Thresholds.minCovered;
    }

    final shapeOk = r.inside >= Thresholds.minInside && r.covered >= Thresholds.minCovered;

    // 크기가 많이 어긋나면 그게 모양이 틀어진 원인이다. 모양 얘기 대신 크기부터 말한다
    var extras = 0;
    if (r.sizeRatio < Thresholds.minSize) {
      extras++;
      deficits.clear();
      deficits[PracticeIssue.size] = (Thresholds.minSize - r.sizeRatio) / Thresholds.minSize;
    } else if (r.sizeRatio > Thresholds.maxSize) {
      extras++;
      deficits.clear();
      deficits[PracticeIssue.size] = (r.sizeRatio - Thresholds.maxSize) / Thresholds.maxSize;
    }

    // 위치·기울기·자간은 모양이 어느 정도 맞을 때만 따진다 (덜 쓴 글씨는 가운데가 쏠려 보여서 엉뚱한 말이 된다)
    if (shapeOk) {
      final offset = math.max(r.offsetX.abs(), r.offsetY.abs());
      if (offset > Thresholds.maxOffset) {
        extras++;
        deficits[PracticeIssue.position] = (offset - Thresholds.maxOffset) / Thresholds.maxOffset;
      }
      final tilt = r.tiltDegrees;
      if (tilt != null && tilt.abs() > Thresholds.maxTiltDegrees) {
        extras++;
        deficits[PracticeIssue.tilt] = (tilt.abs() - Thresholds.maxTiltDegrees) / Thresholds.maxTiltDegrees;
      }
      final tight = r.spacingMin;
      final loose = r.spacingMax;
      if (tight != null && tight < Thresholds.minSpacing) {
        extras++;
        deficits[PracticeIssue.spacing] = Thresholds.minSpacing - tight + 0.1;
      } else if (loose != null && loose > Thresholds.maxSpacing) {
        extras++;
        deficits[PracticeIssue.spacing] = (loose - Thresholds.maxSpacing) / Thresholds.maxSpacing;
      }
    }

    final base = 100 * (r.inside + r.covered) / 2;
    final score = (base - 5 * extras).round().clamp(0, 100).toInt();
    final passed = lenient || shapeOk;

    PracticeIssue? worst;
    var worstDeficit = 0.0;
    deficits.forEach((issue, value) {
      if (value > worstDeficit) {
        worst = issue;
        worstDeficit = value;
      }
    });

    return PracticeVerdict(
      score: score,
      passed: passed,
      issue: worst,
      message: worst == null ? _praise(score) : _sentence(worst!, r, label),
    );
  }

  static String _praise(int score) {
    if (score >= 90) return '아주 잘 썼어요.';
    if (score >= 70) return '잘 썼어요.';
    return '조금 더 연습해 봐요.';
  }

  static String _sentence(PracticeIssue issue, StrokeReport r, String label) {
    switch (issue) {
      case PracticeIssue.shape:
        return '$label의 모양이 보조선과 많이 달라요. 천천히 따라 써 보세요.';
      case PracticeIssue.missing:
        final part = r.worstPartName;
        final unit = r.worstPartUnit;
        if (part != null && unit != null && unit.isNotEmpty) {
          return '$unit에서 $part 부분이 덜 그려졌어요.';
        }
        final direction = r.uncoveredDirection;
        if (direction != null) return '$label의 $direction이 덜 그려졌어요.';
        return '$label이 덜 그려졌어요.';
      case PracticeIssue.size:
        return r.sizeRatio < Thresholds.minSize
            ? '글씨가 너무 작아요. 보조 글자만큼 크게 써 보세요.'
            : '글씨가 너무 커요. 보조 글자만큼만 써 보세요.';
      case PracticeIssue.position:
        final String where;
        if (r.offsetX.abs() >= r.offsetY.abs()) {
          where = r.offsetX < 0 ? '왼쪽으로' : '오른쪽으로';
        } else {
          where = r.offsetY < 0 ? '위로' : '아래로';
        }
        return '글씨가 $where 치우쳤어요. 보조 글자 자리에 맞춰 써 보세요.';
      case PracticeIssue.tilt:
        return (r.tiltDegrees ?? 0) > 0
            ? '글씨가 오른쪽으로 갈수록 내려가요. 줄을 맞춰 써 보세요.'
            : '글씨가 오른쪽으로 갈수록 올라가요. 줄을 맞춰 써 보세요.';
      case PracticeIssue.spacing:
        final tight = (r.spacingMin ?? 1) < Thresholds.minSpacing;
        return tight ? '글자 사이가 너무 좁아요. 조금 띄워 써 보세요.' : '글자 사이가 너무 넓어요. 조금 붙여 써 보세요.';
    }
  }

  /// 점수를 말할 때: "82점이에요."
  static String scoreSentence(int score) => '$score점${ieyo('점')}.';
}

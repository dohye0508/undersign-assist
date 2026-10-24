import 'package:flutter/material.dart';

import '../../models/fill.dart';
import '../../widgets/step_progress.dart';

/// 쓰고 서명하기 화면 맨 위 진행 표시. 칸 하나에 동그라미 하나, 공용 [StepProgress]로 그린다.
///
/// 칸이 폭에 다 들어가지 않으면 줄바꿈·가로 밀기 없이 진행 막대 + "3 / 14" 한 줄로 바뀐다.
/// 칸 이름은 화면에 쓰지 않는다(바로 아래 큰 제목이 지금 칸 이름).
/// 스크린리더에는 "채울 곳 7개 중 3번째, 2개 채움" 한 문장으로 읽힌다.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.targets, required this.filledIds, required this.currentIndex});

  final List<FillTarget> targets;

  /// 이미 채운 칸의 [FillTarget.id]
  final Set<String> filledIds;

  /// 지금 쓰는 칸 (targets 안의 순서). 범위 밖이면(다 채운 뒤) 강조하는 칸이 없다
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final n = targets.length;
    final filled = {
      for (final (i, t) in targets.indexed)
        if (filledIds.contains(t.id)) i,
    };
    final position = currentIndex >= 0 && currentIndex < n ? '${currentIndex + 1}번째' : '모두 봄';
    return StepProgress(
      count: n,
      filled: filled,
      current: currentIndex,
      semanticLabel: '채울 곳 $n개 중 $position, ${filled.length}개 채움',
    );
  }
}

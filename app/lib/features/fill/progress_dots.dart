import 'package:flutter/material.dart';

import '../../models/fill.dart';
import '../../theme/app_theme.dart';

/// 쓰고 서명하기 화면 제목 아래의 진행 동그라미 줄. 칸 하나에 동그라미 하나.
///
/// - 빈 칸: 회색 테두리만
/// - 지금 칸: 강조색 테두리 + 옅은 파랑 둘레
/// - 채운 칸: 강조색으로 채움
/// 칸 이름은 화면에 쓰지 않는다(바로 아래 큰 제목이 지금 칸 이름). 스크린리더에는 진행 상황 한 문장.
/// 칸이 8개를 넘으면 가로로 밀어 볼 수 있다. 스크린리더에는 "채울 곳 7개 중 3번째, 2개 채움" 한 문장으로 읽힌다.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.targets, required this.filledIds, required this.currentIndex});

  final List<FillTarget> targets;

  /// 이미 채운 칸의 [FillTarget.id]
  final Set<String> filledIds;

  /// 지금 쓰는 칸 (targets 안의 순서). 범위 밖이면(다 채운 뒤) 강조하는 칸이 없다
  final int currentIndex;

  static const _size = 16.0;
  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final n = targets.length;
    if (n == 0) return const SizedBox.shrink();
    final filledCount = targets.where((t) => filledIds.contains(t.id)).length;
    final position = currentIndex >= 0 && currentIndex < n ? '${currentIndex + 1}번째' : '모두 봄';
    final dots = [
      for (final (i, t) in targets.indexed)
        _Dot(
          filled: filledIds.contains(t.id),
          current: i == currentIndex,
        ),
    ];
    final row = Row(
      mainAxisAlignment: n > 8 ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (i, dot) in dots.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          dot,
        ],
      ],
    );
    return Semantics(
      label: '채울 곳 $n개 중 $position, $filledCount개 채움',
      child: ExcludeSemantics(
        child: SizedBox(
          height: _size + 12,
          child: n > 8
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: row,
                )
              : row,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled, required this.current});

  final bool filled;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: ProgressDots._duration,
      curve: Curves.easeOut,
      width: ProgressDots._size,
      height: ProgressDots._size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.primary : AppColors.surface,
        border: Border.all(
          color: filled || current ? AppColors.primary : AppColors.grey300,
          width: 2.5,
        ),
        boxShadow: current ? const [BoxShadow(color: AppColors.primarySoft, spreadRadius: 4)] : null,
      ),
    );
  }
}

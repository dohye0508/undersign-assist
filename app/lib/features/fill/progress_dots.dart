import 'package:flutter/material.dart';

import '../../models/fill.dart';
import '../../theme/app_theme.dart';
import 'fill_kind.dart';

/// 쓰고 서명하기 화면 제목 아래의 진행 동그라미 줄. 칸 하나에 동그라미 하나.
///
/// - 빈 칸: 테두리만 ([AppColors.line], 2px)
/// - 지금 칸: 강조색 두꺼운 테두리, 1.25배 크기
/// - 채운 칸: 강조색으로 채우고 흰 ✓
/// 동그라미 아래에는 칸 종류의 짧은 이름(서명·동의·성명·날짜 …)을 작게 적는다.
/// 칸이 8개를 넘으면 가로로 밀어 볼 수 있다. 스크린리더에는 "채울 곳 7개 중 3번째, 2개 채움" 한 문장으로 읽힌다.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.targets, required this.filledIds, required this.currentIndex});

  final List<FillTarget> targets;

  /// 이미 채운 칸의 [FillTarget.id]
  final Set<String> filledIds;

  /// 지금 쓰는 칸 (targets 안의 순서). 범위 밖이면(다 채운 뒤) 강조하는 칸이 없다
  final int currentIndex;

  static const _size = 22.0;
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
          label: t.shortName,
          filled: filledIds.contains(t.id),
          current: i == currentIndex,
        ),
    ];
    final row = Row(
      mainAxisAlignment: n > 8 ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, dot) in dots.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          dot,
        ],
      ],
    );
    return Semantics(
      label: '채울 곳 $n개 중 $position, $filledCount개 채움',
      child: ExcludeSemantics(
        child: SizedBox(
          height: _size * 1.25 + 4 + 16,
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
  const _Dot({required this.label, required this.filled, required this.current});

  final String label;
  final bool filled;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final size = current ? ProgressDots._size * 1.25 : ProgressDots._size;
    final border = filled
        ? Border.all(color: AppColors.primary, width: 2)
        : current
            ? Border.all(color: AppColors.primary, width: 3.5)
            : Border.all(color: AppColors.line, width: 2);
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 크기가 바뀌어도 가운데가 흔들리지 않게 가장 큰 크기의 자리를 잡아 둔다
          SizedBox(
            width: ProgressDots._size * 1.25,
            height: ProgressDots._size * 1.25,
            child: Center(
              child: AnimatedContainer(
                duration: ProgressDots._duration,
                curve: Curves.easeOut,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? AppColors.primary : AppColors.surface,
                  border: border,
                ),
                child: filled ? Icon(Icons.check, size: size * 0.65, color: Colors.white) : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              color: current ? AppColors.primary : AppColors.muted,
              fontWeight: current ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

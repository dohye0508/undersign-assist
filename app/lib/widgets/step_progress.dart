import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 화면 맨 위 진행 표시 한 줄. 쓰고 서명하기(채울 칸)와 들리는 받아쓰기(글자)가 함께 쓴다.
///
/// **절대 줄바꿈하지 않는다.** 높이는 언제나 [height] 한 줄.
/// - 칸이 폭에 다 들어가면 동그라미 한 줄: 채운 칸은 강조색, 지금 칸은 강조색 테두리 + 옅은 파랑 둘레, 빈 칸은 회색 테두리.
/// - 들어가지 않으면 얇은 진행 막대 + 오른쪽 "3 / 14". 막대는 채운 칸 비율만큼 차고,
///   지금 칸 자리에 동그라미 하나(지금 칸 모양)를 얹어 어디쯤인지 보이게 한다.
///
/// 스크린리더에는 [semanticLabel] 한 문장만 읽힌다.
class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.count,
    required this.filled,
    required this.current,
    required this.semanticLabel,
  });

  /// 칸 수
  final int count;

  /// 채운 칸 (0부터)
  final Set<int> filled;

  /// 지금 칸 (0부터). 범위 밖이면(다 채운 뒤) 강조하는 칸이 없다
  final int current;

  /// 스크린리더가 읽을 한 문장 (예: "채울 곳 14개 중 3번째, 2개 채움")
  final String semanticLabel;

  static const dotSize = 14.0;
  static const gap = 10.0;

  /// 지금 칸 둘레(primarySoft)가 번지는 폭
  static const ring = 4.0;

  /// 두 모양 모두 이 높이 한 줄
  static const height = dotSize + ring * 2 + 6;

  static const barHeight = 8.0;
  static const duration = Duration(milliseconds: 250);

  /// [count]개 동그라미 줄이 차지하는 폭 (양끝 둘레 포함)
  static double dotsWidth(int count) => count * dotSize + (count - 1) * gap + ring * 2;

  /// 이 폭에 동그라미가 다 들어가는지
  static bool fitsDots(int count, double maxWidth) => dotsWidth(count) <= maxWidth;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fits = !constraints.hasBoundedWidth || fitsDots(count, constraints.maxWidth);
            return fits ? _dots() : _bar();
          },
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      key: const Key('step-progress-dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          _Dot(key: ValueKey('step-dot-$i'), filled: filled.contains(i), current: i == current),
        ],
      ],
    );
  }

  Widget _bar() {
    final filledCount = filled.where((i) => i >= 0 && i < count).length;
    final hasCurrent = current >= 0 && current < count;
    final shown = hasCurrent ? current + 1 : filledCount;
    return Row(
      key: const Key('step-progress-bar'),
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // 지금 칸 동그라미의 가운데: 칸 하나 너비의 가운데. 양끝 둘레가 잘리지 않게 안쪽으로 붙인다
              final inset = dotSize / 2 + ring;
              final center = hasCurrent ? ((current + 0.5) / count * w).clamp(inset, w - inset) : 0.0;
              return Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: AppColors.grey200,
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),
                  AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOut,
                    height: barHeight,
                    width: w * filledCount / count,
                    decoration: BoxDecoration(
                      color: AppColors.marker,
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),
                  if (hasCurrent)
                    AnimatedPositioned(
                      duration: duration,
                      curve: Curves.easeOut,
                      left: center - dotSize / 2,
                      child: _Dot(filled: filled.contains(current), current: true),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$shown / $count',
          style: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.filled, required this.current});

  final bool filled;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: StepProgress.duration,
      curve: Curves.easeOut,
      width: StepProgress.dotSize,
      height: StepProgress.dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.marker : AppColors.surface,
        border: Border.all(
          color: filled || current ? AppColors.marker : AppColors.grey300,
          width: 2.5,
        ),
        boxShadow: current ? const [BoxShadow(color: AppColors.primarySoft, spreadRadius: StepProgress.ring)] : null,
      ),
    );
  }
}

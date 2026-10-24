import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'practice_items.dart';
import 'score_store.dart';

/// 나의 점수판: 자음 · 모음 · 글자 · 낱말 네 막대 (종류별 최근 점수의 평균)
class ScoreBoardView extends StatelessWidget {
  const ScoreBoardView({super.key, required this.store});

  final ScoreStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final kind in PracticeKind.values) ...[
          _Bar(label: kind.label, score: store.average(kind)),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 4),
        Text(store.boardSpeech(), style: text.bodyLarge),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.score});

  final String label;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = score;
    return Semantics(
      label: value == null ? '$label 아직 연습하지 않았어요' : '$label $value점',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: text.titleLarge),
                const Spacer(),
                Text(value == null ? '아직 없어요' : '$value점', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (value ?? 0) / 100,
                minHeight: 16,
                backgroundColor: AppColors.primarySoft,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

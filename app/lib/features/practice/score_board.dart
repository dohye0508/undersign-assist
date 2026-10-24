import 'package:flutter/material.dart';

import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import '../read/read_panel.dart' show ListenButton;
import 'practice_items.dart';
import 'practice_layout.dart';
import 'score_store.dart';

/// 나의 점수판 (사용자 선택 S1 + W2·W3): 점수 듣기 → 자음·모음·글자·낱말 가로 막대 네 줄(가장 높은 것은 진한 하늘) →
/// "가장 많이 오른 것 / 가장 낮은 글자" 문장 → "글자별 점수" 목록. 맨 아래 고정 버튼은 가장 낮은 글자 다시 써 보기
class ScoreBoardView extends StatelessWidget {
  const ScoreBoardView({super.key, required this.store, this.onRetryLowest, this.onStart});

  final ScoreStore store;

  /// 가장 낮은 글자부터 다시 쓰기. null이면 버튼을 두지 않는다
  final VoidCallback? onRetryLowest;

  /// 아직 점수가 없을 때 맨 아래 버튼: 자음 학습으로. null이면 버튼을 두지 않는다
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final scores = {for (final k in PracticeKind.values) k: store.average(k)};
    final best = scores.entries.where((e) => e.value != null).fold<MapEntry<PracticeKind, int?>?>(
        null, (acc, e) => acc == null || (e.value ?? 0) > (acc.value ?? 0) ? e : acc);
    final lowest = store.lowestItemName();
    final items = store.itemScores();
    return PracticeBottomLayout(
      // 맨 아래 고정 버튼: 가장 낮은 글자 다시 써 보기 (사용자 선택 W2)
      cta: lowest != null && onRetryLowest != null && items.isNotEmpty
          ? PracticeCta('가장 낮은 글자예요 · ${items.first.score}점', '$lowest 다시 써 보기', onRetryLowest!)
          : onStart != null
              ? PracticeCta('아직 점수가 없어요', '자음부터 시작', onStart!)
              : null,
      children: [
        ListenButton(
          label: '점수 듣기',
          icon: Icons.volume_up_rounded,
          onPressed: () => Speech.announce(context, store.boardSpeech()),
        ),
        const SizedBox(height: 18),
        for (final kind in PracticeKind.values) _Bar(label: kind.label, score: scores[kind], lead: best?.key == kind),
        const SizedBox(height: 14),
        Text(store.boardSpeech(), style: Theme.of(context).textTheme.bodyLarge),
        // 아래 빈 곳에 쓸모 있는 목록 (사용자 선택 W3): 글자별 점수, 낮은 것부터
        if (items.isNotEmpty) ...[
          const SectionHeading('글자별 점수'),
          for (final item in items.take(10)) ScoreRow(glyph: item.text, name: item.name, score: item.score),
        ],
      ],
    );
  }
}

/// 이름 · 막대 · 점수 한 줄. 연습하지 않은 종류는 빈 막대와 "아직 없어요"
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.score, required this.lead});

  final String label;
  final int? score;

  /// 가장 높은 종류 (진한 하늘)
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final value = score;
    return Semantics(
      label: value == null ? '$label 아직 연습하지 않았어요' : '$label $value점',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            SizedBox(width: 52, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(
                  value: (value ?? 0) / 100,
                  minHeight: 18,
                  backgroundColor: AppColors.grey100,
                  color: lead ? AppColors.accent : AppColors.marker,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text(
                value == null ? '아직 없어요' : '$value점',
                textAlign: TextAlign.right,
                style: value == null
                    ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)
                    : const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

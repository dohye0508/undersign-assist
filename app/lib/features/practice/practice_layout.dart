import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';

/// 맨 아래 고정 버튼의 내용: 위 작은 안내 한 줄 + 버튼 글자 + 누르면 할 일
class PracticeCta {
  const PracticeCta(this.hint, this.label, this.onPressed);

  final String hint;
  final String label;
  final VoidCallback onPressed;
}

/// 받아쓰기 메뉴·점수판 공통 틀 (사용자 선택 W2+W3): 위는 스크롤되는 내용, 맨 아래는 늘 같은 자리의 큰 버튼 하나.
/// 화면을 보지 않는 사용자도 "맨 아래 = 다음에 할 일"로 외울 수 있다
class PracticeBottomLayout extends StatelessWidget {
  const PracticeBottomLayout({super.key, required this.children, required this.cta});

  final List<Widget> children;
  final PracticeCta? cta;

  @override
  Widget build(BuildContext context) {
    final cta = this.cta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: children),
        ),
        if (cta != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  cta.hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: TapFeedback.wrap(cta.onPressed),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(68),
                    backgroundColor: AppColors.primaryStrong,
                    textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text(cta.label, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 글자 한 줄: 큰 보기 글자 · 이름 · 점수 (70점 미만은 노랑 글자)
class ScoreRow extends StatelessWidget {
  const ScoreRow({super.key, required this.glyph, required this.name, required this.score});

  final String glyph;
  final String name;
  final int score;

  @override
  Widget build(BuildContext context) {
    final low = score < 70;
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.grey100))),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(glyph, style: const TextStyle(fontFamily: 'DoHyeon', fontSize: 28, color: AppColors.accent)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text))),
            Text(
              '$score점',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: low ? AppColors.missing : AppColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

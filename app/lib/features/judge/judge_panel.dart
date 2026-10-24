import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 판단: 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다.
/// 지금은 화면만 있다. 기능을 만들 때 [ApiClient.judge] 결과로 아래 예시 카드를 바꾼다.
class JudgePanel extends StatelessWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: '빠진 것 확인',
      description: '빠진 항목과 확인이 필요한 내용을 근거와 함께 알려드려요. 결정은 직접 하세요.',
      preparing: true,
      children: [
        const FilledButton(onPressed: null, child: Text('판단 듣기')),
        const SizedBox(height: 20),
        Text('결과는 이렇게 보여요 (화면 예시)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        const _FindingCard(
          kind: _Kind.ok,
          item: '계약 기간',
          reason: '시작일과 끝나는 날이 모두 적혀 있어요.',
        ),
        const _FindingCard(
          kind: _Kind.missing,
          item: '쉬는 날',
          reason: '근로계약서에 있어야 하는 항목인데 찾지 못했어요.',
        ),
        const _FindingCard(
          kind: _Kind.caution,
          item: '임금',
          reason: '기준과 비교해 확인이 필요해 보여요.',
          evidence: '문서 원문: "시간급 ○○원"',
        ),
      ],
    );
  }
}

enum _Kind {
  ok('확인됨', Icons.check_circle_outline, AppColors.ok, AppColors.okSoft),
  missing('빠짐', Icons.help_outline, AppColors.missing, AppColors.missingSoft),
  caution('확인 필요', Icons.error_outline, AppColors.caution, AppColors.cautionSoft);

  const _Kind(this.label, this.icon, this.color, this.background);

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.kind, required this.item, required this.reason, this.evidence});

  final _Kind kind;
  final String item;
  final String reason;
  final String? evidence;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kind.background, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(kind.icon, color: kind.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${kind.label} · $item', style: TextStyle(color: kind.color, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(reason, style: Theme.of(context).textTheme.bodyMedium),
                  if (evidence != null) Text(evidence!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

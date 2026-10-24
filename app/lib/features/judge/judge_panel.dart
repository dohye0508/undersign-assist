import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 판단: 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다.
/// 지금은 화면만 있다 (디자인 시안의 "분석 결과" 카드 모양). 기능을 만들 때 ApiClient.judge 결과로 예시 카드를 바꾼다.
class JudgePanel extends StatelessWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: '판단',
      description: '빠진 항목과 확인이 필요한 내용을 근거와 함께 알려드려요. 결정은 직접 하세요.',
      preparing: true,
      children: [
        const Row(
          children: [
            StatTile(value: '–', label: '확인됨'),
            SizedBox(width: 8),
            StatTile(value: '–', label: '확인 필요', highlight: true),
            SizedBox(width: 8),
            StatTile(value: '–', label: '빠진 항목'),
          ],
        ),
        const SizedBox(height: 12),
        Text('결과는 이렇게 보여요 (화면 예시)', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        const _FindingCard(
          kind: _Kind.caution,
          title: '확인이 필요한 조항이 있어요',
          body: '문서의 해당 문장과 비교한 기준을 함께 읽어드려요.',
          basis: '근거 법 조항',
        ),
        const SizedBox(height: 10),
        const _FindingCard(
          kind: _Kind.missing,
          title: '있어야 할 항목이 보이지 않아요',
          body: '근로계약서라면 쉬는 날, 임금 지급 방법 같은 항목이 있어야 해요.',
        ),
        const SizedBox(height: 14),
        const FilledButton(onPressed: null, child: Text('판단 듣기')),
      ],
    );
  }
}

enum _Kind {
  caution(Icons.warning_amber_rounded, AppColors.warning, AppColors.warningSoft),
  missing(Icons.help_outline_rounded, AppColors.danger, AppColors.dangerSoft);

  const _Kind(this.icon, this.color, this.background);

  final IconData icon;
  final Color color;
  final Color background;
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.kind, required this.title, required this.body, this.basis});

  final _Kind kind;
  final String title;
  final String body;

  /// 근거가 된 법 조항 이름 (디자인 시안의 오른쪽 위 꼬리표)
  final String? basis;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: kind.background,
                  child: Icon(kind.icon, size: 18, color: kind.color),
                ),
                const Spacer(),
                if (basis != null) Pill(basis!, color: Colors.white, background: kind.color),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/judgement.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import 'judgement.dart';

/// 판단("검토하세요!"): 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다.
/// 판정은 백엔드 규칙 엔진(backend/app/services/judge)이 한다. 이 화면은 결과를 보여주고 읽어주기만 한다.
class JudgePanel extends StatefulWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<JudgePanel> createState() => _JudgePanelState();
}

class _JudgePanelState extends State<JudgePanel> {
  @override
  void initState() {
    super.initState();
    // 창이 열리면 바로 판단하고 요약을 들려준다
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final judgement = await widget.state.judge();
      if (!mounted) return;
      Speech.announce(context, judgement?.speech ?? widget.state.judgeError ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final judgement = state.judgement;
    final text = Theme.of(context).textTheme;

    final List<Widget> body;
    if (state.judging || (judgement == null && state.judgeError == null)) {
      body = [const LinearProgressIndicator(), const SizedBox(height: 12), const Text('규칙과 법 조항으로 검토하고 있어요…')];
    } else if (judgement == null) {
      body = [
        Text(state.judgeError!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: state.judge, child: const Text('다시 검토하기')),
      ];
    } else {
      final caution = judgement.counts['caution'] ?? 0;
      final missing = judgement.counts['missing'] ?? 0;
      body = [
        FilledButton.icon(
          onPressed: () => Speech.announce(context, judgement.speech),
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('검토 결과 듣기'),
        ),
        const SizedBox(height: 14),
        Text('확인이 필요한 곳 $caution개 · 빠진 항목 $missing개', style: text.titleMedium),
        const SizedBox(height: 10),
        for (final finding in _ordered(judgement.findings)) _FindingCard(finding: finding),
        if (judgement.findings.isEmpty) Text('특별히 확인이 필요한 항목을 찾지 못했어요.', style: text.bodyLarge),
        const SizedBox(height: 6),
        Text(judgement.disclaimer.isNotEmpty ? judgement.disclaimer : '최종 판단은 직접 하세요.', style: text.bodyMedium),
      ];
    }

    return PanelSection(
      title: WorkStep.judge.label,
      description: '빠진 항목과 확인이 필요한 내용을 근거와 함께 알려드려요. 결정은 직접 하세요.',
      children: body,
    );
  }

  /// 확인 필요(심각한 것부터) → 빠짐 → 알아두기 순서
  static List<Finding> _ordered(List<Finding> findings) {
    const level = {'caution': 0, 'missing': 1, 'info': 2, 'ok': 3};
    const severity = {'critical': 0, 'high': 1, 'medium': 2, 'info': 3};
    return [...findings]
      ..sort((a, b) {
        final byLevel = (level[a.level] ?? 9).compareTo(level[b.level] ?? 9);
        return byLevel != 0 ? byLevel : (severity[a.severity] ?? 9).compareTo(severity[b.severity] ?? 9);
      });
  }
}

enum _Kind {
  ok('확인됨', Icons.check_circle_outline, AppColors.ok, AppColors.okSoft),
  missing('빠짐', Icons.help_outline, AppColors.missing, AppColors.missingSoft),
  caution('확인 필요', Icons.error_outline, AppColors.caution, AppColors.cautionSoft),
  info('알아두기', Icons.info_outline, AppColors.primary, AppColors.primarySoft);

  const _Kind(this.label, this.icon, this.color, this.background);
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  static _Kind of(String level) => values.firstWhere((k) => k.name == level, orElse: () => info);
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final kind = _Kind.of(finding.level);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kind.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(kind.icon, color: kind.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${kind.label} · ${finding.item}', style: TextStyle(color: kind.color, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(finding.speech.isNotEmpty ? finding.speech : finding.reason, style: text.bodyLarge),
                      if (finding.basis.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('근거: ${finding.basis.map((b) => b.label).join(', ')}', style: text.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Speech.announce(context, _detail(finding)),
              icon: const Icon(Icons.volume_up_outlined, size: 20),
              label: const Text('근거 듣기'),
            ),
          ),
        ],
      ),
    );
  }

  /// 결과 문장, 비교한 기준, 법 조항 이름을 차례로 읽어준다
  static String _detail(Finding f) => [
        f.speech,
        if (f.reason.isNotEmpty) '비교한 기준: ${f.reason}.',
        if (f.basis.isNotEmpty) '근거는 ${f.basis.map((b) => b.label).join(', ')}이에요.',
      ].join(' ');
}

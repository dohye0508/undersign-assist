import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 서명: 판단 결과를 다시 듣고, 서명란 위치를 안내받고, 마지막으로 동의 여부를 확인한다.
/// 지금은 화면만 있다. 기능을 만들 때 [ApiClient.locateSignature]를 쓴다.
class SignPanel extends StatelessWidget {
  const SignPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return const PanelSection(
      title: '서명 위치',
      description: '서명하기 전에 아래 세 가지를 차례로 해요.',
      preparing: true,
      children: [
        _SignStep(number: 1, title: '판단 결과 다시 듣기', detail: '확인이 필요한 항목이 있으면 서명 전에 한 번 더 알려드려요.', action: '다시 듣기'),
        _SignStep(number: 2, title: '서명란 찾기', detail: '서명란이 펜보다 어느 쪽에 있는지 소리로 안내해요.', action: '서명란 찾기'),
        _SignStep(number: 3, title: '서명 전 확인', detail: '이 문서에 서명할지 마지막으로 물어봐요.', action: '확인하기'),
      ],
    );
  }
}

class _SignStep extends StatelessWidget {
  const _SignStep({required this.number, required this.title, required this.detail, required this.action});

  final int number;
  final String title;
  final String detail;
  final String action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$number. $title', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(detail, style: text.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: null, child: Text(action)),
        ],
      ),
    );
  }
}

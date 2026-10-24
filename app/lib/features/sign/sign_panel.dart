import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 서명: 판단 결과를 다시 듣고, 서명이 필요한 곳을 안내받고, 마지막으로 동의 여부를 확인한다.
/// 지금은 화면만 있다 (디자인 시안의 "서명이 필요한 곳" 목록 모양). 기능을 만들 때 ApiClient.locateSignature를 쓴다.
class SignPanel extends StatelessWidget {
  const SignPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelSection(
      title: '서명',
      description: '서명하기 전에 판단 결과를 한 번 더 들려드리고, 서명할 곳을 소리로 안내해요.',
      preparing: true,
      children: [
        const AppCard(
          color: AppColors.warningSoft,
          child: Row(
            children: [
              Icon(Icons.volume_up_rounded, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(child: Text('서명 전, 판단 결과를 다시 들어보실 수 있어요')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('서명이 필요한 곳 (화면 예시)', style: text.labelLarge),
        const SizedBox(height: 8),
        const _SignSpot(label: '근로자 서명란'),
        const SizedBox(height: 8),
        const _SignSpot(label: '보호자 서명란'),
        const SizedBox(height: 16),
        const FilledButton(onPressed: null, child: Text('서명하러 가기')),
      ],
    );
  }
}

class _SignSpot extends StatelessWidget {
  const _SignSpot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.text,
            child: Icon(Icons.edit_outlined, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
        ],
      ),
    );
  }
}

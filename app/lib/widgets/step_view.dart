import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'big_button.dart';

/// 네 단계가 함께 쓰는 틀: 제목, 설명, 큰 버튼 하나, 결과 칸.
/// 단계마다 모양이 같아야 화면을 외워서 쓰는 사용자가 헷갈리지 않는다.
class StepView extends StatelessWidget {
  const StepView({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.result,
    this.busy = false,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? result;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Semantics(header: true, child: Text(title, style: text.headlineSmall)),
        const SizedBox(height: 8),
        Text(description, style: text.bodyMedium),
        const SizedBox(height: 24),
        BigButton(label: busy ? '잠시만요…' : actionLabel, onPressed: busy ? null : onAction),
        const SizedBox(height: 24),
        if (result != null)
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line, width: 2),
              ),
              child: Text(result!, style: text.bodyLarge),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 오른쪽 패널에서 단계 내용을 담는 틀: 제목, 설명, 그 아래 내용.
class PanelSection extends StatelessWidget {
  const PanelSection({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.preparing = false,
    this.actions = const [],
  });

  final String title;
  final String description;
  final List<Widget> children;

  /// 기능은 아직 없고 화면만 있는 단계
  final bool preparing;

  /// 제목 줄 오른쪽 끝의 작은 버튼들 (예: 다시 듣기). 내용을 가리지 않게 제목 옆에 둔다.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // 글자를 크게 키워도 버튼이 밀려나지 않게 제목 쪽이 남는 폭을 맡는다
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Semantics(header: true, child: Text(title, style: text.titleLarge))),
                  if (preparing) ...[
                    const SizedBox(width: 10),
                    const Chip(label: Text('준비 중'), visualDensity: VisualDensity.compact),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 4),
        Text(description, style: text.bodyMedium),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

/// 이름과 값 한 쌍 (예: 임금 / 시간급 9,000원)
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 104, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

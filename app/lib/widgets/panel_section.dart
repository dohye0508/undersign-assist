import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tap_feedback.dart';

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
        const SizedBox(height: 2),
        Text(description, style: text.bodyMedium),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// 구역 제목. 위에 화면 끝까지 닿는 굵은 회색 띠(10px)를 두어 구역을 나눈다 (토스식, 카드 테두리 대신).
/// 부모의 좌우 여백이 16이라고 보고 그만큼 바깥으로 띠를 늘린다.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key});

  final String title;

  static const bleed = 16.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 26),
        SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, c) => OverflowBox(
              minWidth: c.maxWidth + bleed * 2,
              maxWidth: c.maxWidth + bleed * 2,
              child: const ColoredBox(color: AppColors.grey100, child: SizedBox.expand()),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
          child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ),
      ],
    );
  }
}

/// 이름과 값 한 쌍 (예: 임금 / 시간급 9,000원). 이름은 왼쪽 회색, 값은 오른쪽 굵게
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.grey100))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted, height: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                // 짧은 값은 오른쪽 끝에, 여러 줄로 넘어가는 긴 값은 읽기 쉽게 왼쪽 정렬
                textAlign: value.length <= 18 ? TextAlign.right : TextAlign.left,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "다음에 할 일" 줄 버튼: 굵은 제목 + 작은 설명 + 오른쪽 ›. primary면 강조색으로 꽉 찬다
class NextStepButton extends StatelessWidget {
  const NextStepButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.text;
    final sub = primary ? Colors.white.withValues(alpha: 0.85) : AppColors.muted;
    final radius = BorderRadius.circular(AppRadius.button);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: primary ? AppColors.primary : AppColors.grey100,
        borderRadius: radius,
        child: InkWell(
          onTap: TapFeedback.wrap(onPressed),
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: sub)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 26, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

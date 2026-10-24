import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 흰 카드. 디자인 시안의 카드처럼 둥근 모서리와 아주 옅은 그림자.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}

/// 둥근 작은 꼬리표 (예: "준비 중", "AI로 정리")
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.primary, this.background = AppColors.primarySoft});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// 오른쪽 패널에서 단계 내용을 담는 틀: 제목, 설명, 그 아래 내용.
class PanelSection extends StatelessWidget {
  const PanelSection({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.preparing = false,
  });

  final String title;
  final String description;
  final List<Widget> children;

  /// 기능은 아직 없고 화면만 있는 단계
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(header: true, child: Text(title, style: text.headlineSmall)),
            if (preparing) ...[const SizedBox(width: 10), const Pill('준비 중')],
          ],
        ),
        const SizedBox(height: 2),
        Text(description, style: text.bodyMedium),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }
}

/// 숫자나 짧은 값 하나를 크게 보여주는 칸 (분석 결과 위쪽의 세 칸)
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.highlight = false});

  final String value;
  final String label;

  /// 주의가 필요한 값 (호박색 배경)
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MergeSemantics(
        child: AppCard(
          color: highlight ? AppColors.warningSoft : null,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: highlight ? AppColors.warning : AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: highlight ? AppColors.warningDark : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 이름과 값 한 쌍 (예: 임금 / 시간급 9,000원)
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({super.key, required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

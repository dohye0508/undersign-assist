import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 화면을 보기 어려운 사용자도 쉽게 누를 수 있는 큰 버튼.
/// raibitScoreboard의 호박색 테두리 버튼 모양을 따른다.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.hint,
    this.height = 96,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 스크린리더가 버튼 이름 뒤에 읽어줄 설명
  final String? hint;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: hint,
      excludeSemantics: true,
      label: label,
      child: SizedBox(
        height: height,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.amber,
            backgroundColor: AppColors.panel,
            side: const BorderSide(color: AppColors.amber, width: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            textStyle: const TextStyle(fontFamily: AppFonts.display, fontSize: 34),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 40), const SizedBox(width: 16)],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

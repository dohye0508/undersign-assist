import 'package:flutter/material.dart';

/// 흰 바탕에 아주 옅은 유색 그라데이션을 얹은 밝은 테마.
/// 저시력 사용자를 위해 글씨와 터치 영역은 크게, 글자 대비는 높게 잡는다.
class AppColors {
  static const background = Color(0xFFF8F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE3E7F0);
  static const text = Color(0xFF1B1F2B);
  static const muted = Color(0xFF5E6577);
  static const subtle = Color(0xFF8A91A3);

  static const primary = Color(0xFF4A63E7);
  static const primarySoft = Color(0xFFEEF1FE);

  // 판단 결과의 의미 색. 강조색과 따로 쓴다
  static const ok = Color(0xFF2B8A3E);
  static const okSoft = Color(0xFFEBF8EE);
  static const missing = Color(0xFFB35C00);
  static const missingSoft = Color(0xFFFFF4E5);
  static const caution = Color(0xFFC92A2A);
  static const cautionSoft = Color(0xFFFFF0F0);

  /// 화면 전체에 깔리는 아주 옅은 그라데이션 (파랑 → 흰색 → 민트)
  static const pageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEFF2FF), Color(0xFFFFFFFF), Color(0xFFEEFAF5)],
    stops: [0, 0.55, 1],
  );

  /// 선택된 항목, 머리 부분에 쓰는 옅은 그라데이션 (파랑 → 보라)
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEEF1FE), Color(0xFFF5F0FF)],
  );
}

class AppFonts {
  /// 제목
  static const display = 'DoHyeon';

  /// 본문, 버튼, 안내 문장
  static const body = 'Jua';
}

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      outline: AppColors.line,
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const buttonText = TextStyle(fontFamily: AppFonts.body, fontSize: 20);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontFamily: AppFonts.display, fontSize: 34, color: AppColors.text),
        titleLarge: TextStyle(fontFamily: AppFonts.display, fontSize: 26, color: AppColors.text),
        titleMedium: TextStyle(fontSize: 19, color: AppColors.text),
        bodyLarge: TextStyle(fontSize: 19, color: AppColors.text, height: 1.55),
        bodyMedium: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
        labelLarge: TextStyle(fontSize: 15, color: AppColors.subtle, letterSpacing: 0.3),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.line, width: 1.5),
          backgroundColor: AppColors.surface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 17),
        ),
      ),
      focusColor: AppColors.primary.withValues(alpha: 0.18),
    );
  }
}

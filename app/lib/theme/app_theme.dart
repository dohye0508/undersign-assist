import 'package:flutter/material.dart';

/// raibitScoreboard의 색과 글꼴을 따른다: 어두운 바탕, 호박색 강조, 도현체 제목.
/// 저시력 사용자를 위해 글씨와 터치 영역은 크게, 대비는 높게 잡는다.
class AppColors {
  static const background = Color(0xFF140A09);
  static const panel = Color(0xFF1C0F0D);
  static const panelRaised = Color(0xFF2A1714);
  static const line = Color(0xFF5A3A33);
  static const text = Color(0xFFF3E6E1);
  static const muted = Color(0xFFC9B3AC);
  static const amber = Color(0xFFFFB21E);
  static const red = Color(0xFFFF4A1C);
}

class AppFonts {
  /// 제목, 버튼
  static const display = 'DoHyeon';

  /// 본문, 안내 문장
  static const body = 'Jua';
}

class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.amber,
      onPrimary: AppColors.background,
      secondary: AppColors.red,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      outline: AppColors.line,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontFamily: AppFonts.display, fontSize: 48, color: AppColors.amber),
        headlineSmall: TextStyle(fontFamily: AppFonts.display, fontSize: 30, color: AppColors.text),
        titleLarge: TextStyle(fontFamily: AppFonts.display, fontSize: 26, color: AppColors.text),
        bodyLarge: TextStyle(fontSize: 22, color: AppColors.text, height: 1.5),
        bodyMedium: TextStyle(fontSize: 19, color: AppColors.muted, height: 1.5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.amber,
        titleTextStyle: TextStyle(fontFamily: AppFonts.display, fontSize: 28, color: AppColors.amber),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.amber,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.amber,
        labelStyle: TextStyle(fontFamily: AppFonts.display, fontSize: 24),
        unselectedLabelStyle: TextStyle(fontFamily: AppFonts.display, fontSize: 24),
      ),
      focusColor: AppColors.amber.withValues(alpha: 0.35),
    );
  }
}

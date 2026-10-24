import 'package:flutter/material.dart';

/// 팀 디자인 시안(`Undersign 촬영 화면.html`)의 색과 글꼴.
/// 밝은 회청색 바탕, 흰 카드, 남색 글자, 파란 강조, 경고는 호박색, 카메라 틀은 짙은 남색.
class AppColors {
  static const background = Color(0xFFF4F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE3E8F2);
  static const text = Color(0xFF1B2F5E);
  static const muted = Color(0xFF566074);
  static const subtle = Color(0xFF8A93A6);

  static const primary = Color(0xFF2F6FDE);
  static const primarySoft = Color(0xFFE4ECFC);

  // 판단 결과의 의미 색. 강조색과 따로 쓴다
  static const ok = Color(0xFF2B8A3E);
  static const okSoft = Color(0xFFEAF7EE);
  static const warning = Color(0xFFB4700A);
  static const warningDark = Color(0xFF8A5B10);
  static const warningSoft = Color(0xFFFFF4E3);
  static const danger = Color(0xFFC8663A);
  static const dangerSoft = Color(0xFFFCEDE6);

  // 카메라 틀
  static const cameraTop = Color(0xFF141D38);
  static const cameraBottom = Color(0xFF0D1326);
  static const recording = Color(0xFFFF5B5B);

  static const cardShadow = [BoxShadow(color: Color(0x141B2F5E), blurRadius: 3, offset: Offset(0, 1))];
  static const buttonShadow = [BoxShadow(color: Color(0x592F6FDE), blurRadius: 18, offset: Offset(0, 10))];
}

class AppFonts {
  /// 화면 전체
  static const body = 'NotoSansKR';

  /// 앱 이름 글자에만 쓴다
  static const logo = 'DoHyeon';
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
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonText = TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.text, height: 1.55),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.subtle),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          shape: buttonShape,
          textStyle: buttonText,
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.line,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.line, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: const ChipThemeData(
        side: BorderSide.none,
        shape: StadiumBorder(),
        labelStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      focusColor: AppColors.primary.withValues(alpha: 0.16),
    );
  }
}

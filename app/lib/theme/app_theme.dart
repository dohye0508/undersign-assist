import 'package:flutter/material.dart';

/// 토스(Toss) 스타일: 흰 바탕, 포인트 색은 파랑 하나, 카드 테두리 대신 굵은 회색 띠와 여백으로 구역을 나눈다.
/// 저시력 사용자를 위해 버튼 높이는 64 이상, 글자 대비는 4.5:1 이상을 지킨다.
/// 값은 디자인 후보 A(토스형) 시안을 그대로 옮겼다.
class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);

  // 토스 회색 단계
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF2F4F6);
  static const grey200 = Color(0xFFE5E8EB);
  static const grey300 = Color(0xFFD1D6DB);

  /// 얇은 구분선
  static const line = grey100;
  static const text = Color(0xFF191F28);
  static const textStrong = Color(0xFF333D4B);
  static const muted = Color(0xFF6B7684);
  static const subtle = Color(0xFF8B95A1);

  static const primary = Color(0xFF0064FF);
  static const primarySoft = Color(0xFFE8F2FF);

  // 판단 결과의 의미 색. 강조색과 따로 쓴다
  static const ok = Color(0xFF1B7F3B);
  static const okSoft = Color(0xFFE9F7EE);
  static const missing = Color(0xFFB42318);
  static const missingSoft = Color(0xFFFEECEB);
  static const caution = Color(0xFFC2410C);
  static const cautionSoft = Color(0xFFFFF1E6);

  /// 카메라 바탕
  static const camera = Color(0xFF101318);
}

class AppFonts {
  /// 제목과 본문 모두 Pretendard (OFL, assets에 포함)
  static const display = 'Pretendard';
  static const body = 'Pretendard';
}

/// 모서리 둥글기
class AppRadius {
  static const button = 14.0;
  static const card = 16.0;
  static const camera = 24.0;
}

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      outline: AppColors.grey200,
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
    const buttonText = TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.3),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.6),
        bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textStrong, height: 1.55),
        bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.5),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          shape: buttonShape,
          textStyle: buttonText,
          iconSize: 22,
          elevation: 0,
        ),
      ),
      // 토스의 "약한 버튼": 테두리 없이 회색 바탕
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          shape: buttonShape,
          textStyle: buttonText,
          iconSize: 22,
          foregroundColor: AppColors.textStrong,
          side: BorderSide.none,
          backgroundColor: AppColors.grey100,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(52, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700),
          iconSize: 18,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(52, 52),
          iconSize: 22,
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.grey100,
          shape: buttonShape,
        ),
      ),
      chipTheme: const ChipThemeData(
        labelStyle: TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textStrong),
        backgroundColor: AppColors.grey100,
        side: BorderSide.none,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.grey100, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.grey100),
      focusColor: AppColors.primary.withValues(alpha: 0.18),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 들리는계약서 로고 (2026-10-25 사용자가 후보 C "헤드폰 문서"를 고르고, 파란 부분을 모두 검정으로 정함):
/// 검은 둥근 바탕 위에 흰 헤드폰과 흰 문서, 문서 안 줄은 검정.
/// 64 x 64 안에서 그린 그림을 [size]에 맞춰 키운다. 스크린리더에는 읽히지 않는다(제목 글자가 이름을 읽는다).
/// 웹 아이콘(favicon, PWA)도 같은 그림이다: 바꾸면 `app/web/icons`와 `favicon.png`도 다시 만든다
/// (scripts/make_icons.py).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: _LogoPainter()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 64;
    const ink = AppColors.logoInk;
    final white = Paint()..color = Colors.white;

    // 바탕
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(14 * u)),
      Paint()..color = ink,
    );

    // 머리띠: 왼쪽 위로 올라가 반원을 돌아 오른쪽으로 내려온다
    final band = Path()
      ..moveTo(12 * u, 38 * u)
      ..lineTo(12 * u, 32 * u)
      ..arcTo(Rect.fromCircle(center: Offset(32 * u, 32 * u), radius: 20 * u), math.pi, math.pi, false)
      ..lineTo(52 * u, 38 * u);
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.6 * u
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );

    // 귀덮개 둘
    for (final x in [7.0, 47.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * u, 35 * u, 10 * u, 17 * u), Radius.circular(5 * u)), white);
    }

    // 가운데 문서와 줄 셋
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(22 * u, 28 * u, 20 * u, 26 * u), Radius.circular(3.5 * u)), white);
    final line = Paint()..color = ink;
    for (final (y, w) in [(35.0, 12.0), (41.0, 12.0), (47.0, 7.0)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(26 * u, y * u, w * u, 2.8 * u), Radius.circular(1.4 * u)), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

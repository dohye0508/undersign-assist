import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 흰 바탕 곳곳에 아주 옅은 색이 번진 배경. 위치와 색은 `AppColors.blobs`에서 정한다.
class SoftBlobBackground extends StatelessWidget {
  const SoftBlobBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: AppColors.background)),
            for (final blob in AppColors.blobs)
              Positioned(
                left: size.width * blob.x - blob.radius,
                top: size.height * blob.y - blob.radius,
                width: blob.radius * 2,
                height: blob.radius * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [blob.color, blob.color.withValues(alpha: 0)]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

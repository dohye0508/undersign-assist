import 'package:flutter/material.dart';

import '../services/camera_service.dart';
import '../theme/app_theme.dart';
import 'tap_feedback.dart';

/// 카메라 영역. 촬영 화면에서는 늘 카메라만 보여준다 (찍은 페이지는 위쪽 페이지 목록에서 본다).
class DocumentStage extends StatelessWidget {
  const DocumentStage({super.key, required this.camera});

  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (camera.error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                camera.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: TapFeedback.wrap(camera.start),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('카메라 다시 켜기'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              ),
            ],
          ),
        ),
      );
    } else if (camera.ready) {
      // 미리보기 위에 네 모서리 안내선과 한 줄 안내 (보는 사람용 보조. 음성 안내는 따로 한다)
      content = Stack(
        fit: StackFit.expand,
        children: [
          camera.preview(),
          const ExcludeSemantics(child: CustomPaint(painter: _CornerGuides())),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: ExcludeSemantics(
              child: Text(
                '문서를 네모 안에 맞춰 주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      content = const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.camera),
      child: ColoredBox(color: AppColors.camera, child: content),
    );
  }
}

/// 네 모서리의 둥근 ㄱ자 안내선
class _CornerGuides extends CustomPainter {
  const _CornerGuides();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 28.0, len = 34.0, r = 10.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final box = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset - 48);
    for (final (corner, dx, dy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomLeft, 1.0, -1.0),
      (box.bottomRight, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * len)
        ..lineTo(corner.dx, corner.dy + dy * r)
        ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * r, corner.dy)
        ..lineTo(corner.dx + dx * len, corner.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerGuides oldDelegate) => false;
}

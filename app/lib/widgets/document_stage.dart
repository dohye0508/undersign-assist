import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/recognized_document.dart';
import '../models/workspace_state.dart';
import '../services/camera_service.dart';
import '../theme/app_theme.dart';

/// 왼쪽 큰 영역. 사진이 없으면 카메라를, 있으면 그 사진을 보여준다.
/// 디자인 시안의 촬영 화면처럼 짙은 남색 틀, 네 귀퉁이 표시, 왼쪽 위 상태 꼬리표를 둔다.
/// 읽기가 끝나면 인식한 줄의 위치를 사진 위에 표시한다 (곁에서 돕는 사람과 발표용).
class DocumentStage extends StatelessWidget {
  const DocumentStage({super.key, required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    final photo = state.photo;
    final controller = camera.controller;

    final Widget content;
    if (photo != null) {
      content = Semantics(
        image: true,
        label: '받은 문서 사진',
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _PhotoWithBoxes(bytes: photo.bytes, document: state.recognized),
        ),
      );
    } else if (camera.error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            camera.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.6),
          ),
        ),
      );
    } else if (controller != null && camera.ready) {
      content = Center(child: CameraPreview(controller));
    } else {
      content = const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.cameraTop, AppColors.cameraBottom],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          const IgnorePointer(child: CustomPaint(painter: _CornerPainter())),
          Positioned(left: 20, top: 20, child: _StatusPill(state: state, camera: camera)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    final (label, live) = switch (state) {
      _ when state.reading => ('인식 중', true),
      _ when state.recognized != null => (state.recognized!.docTypeLabel, false),
      _ when state.hasPhoto => ('사진', false),
      _ when camera.ready => ('카메라 켜짐', true),
      _ when camera.error != null => ('카메라 없음', false),
      _ => ('카메라 준비 중', false),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xB80A0E1C), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.recording, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 문서를 맞춰 놓을 자리를 알려주는 네 귀퉁이 표시
class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 24.0, length = 34.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * length)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + dx * length, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _PhotoWithBoxes extends StatelessWidget {
  const _PhotoWithBoxes({required this.bytes, required this.document});

  final Uint8List bytes;
  final RecognizedDocument? document;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.contain),
          if (document != null && document.imageWidth > 0)
            CustomPaint(painter: _BoxPainter(document, constraints.biggest)),
        ],
      ),
    );
  }
}

/// 사진을 BoxFit.contain으로 그렸을 때와 같은 비율로 줄 위치를 그린다. 찾은 항목의 줄은 진하게.
class _BoxPainter extends CustomPainter {
  _BoxPainter(this.document, this.area);

  final RecognizedDocument document;
  final Size area;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = [area.width / document.imageWidth, area.height / document.imageHeight]
        .reduce((a, b) => a < b ? a : b);
    final dx = (area.width - document.imageWidth * scale) / 2;
    final dy = (area.height - document.imageHeight * scale) / 2;

    final fieldLines = {for (final f in document.fields) f.line};
    for (final (i, block) in document.blocks.indexed) {
      final b = block.box;
      final rect = Rect.fromLTWH(dx + b.x * scale, dy + b.y * scale, b.width * scale, b.height * scale);
      final isField = fieldLines.contains(i);
      final shape = RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(4));
      if (isField) {
        canvas.drawRRect(shape, Paint()..color = AppColors.primary.withValues(alpha: 0.12));
      }
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isField ? 2 : 1
          ..color = AppColors.primary.withValues(alpha: isField ? 0.9 : 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.document != document || old.area != area;
}

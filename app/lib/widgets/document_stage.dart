import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/recognized_document.dart';
import '../models/workspace_state.dart';
import '../services/camera_service.dart';
import '../theme/app_theme.dart';

/// 화면의 큰 영역. 사진이 없으면 카메라를, 있으면 그 사진을 보여준다.
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
        child: _PhotoWithBoxes(bytes: photo.bytes, document: state.recognized),
      );
    } else if (camera.error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            camera.error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    } else if (controller != null && camera.ready) {
      content = Center(child: CameraPreview(controller));
    } else {
      content = const Center(child: CircularProgressIndicator());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: photo == null ? const Color(0xFF111318) : AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(left: 16, top: 16, child: _StatusChip(state: state, camera: camera)),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      _ when state.reading => '읽는 중…',
      _ when state.recognized != null => state.recognized!.docTypeLabel,
      _ when state.hasPhoto => '사진',
      _ when camera.ready => '카메라',
      _ when camera.error != null => '카메라 없음',
      _ => '카메라 준비 중',
    };
    return Chip(label: Text(label), backgroundColor: AppColors.surface);
  }
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

/// 사진을 BoxFit.contain으로 그렸을 때와 같은 비율로 줄 위치를 그린다.
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
      canvas.drawRect(
        rect.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isField ? 2.5 : 1
          ..color = AppColors.primary.withValues(alpha: isField ? 0.9 : 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.document != document || old.area != area;
}

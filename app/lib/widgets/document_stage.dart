import 'package:flutter/material.dart';

import '../services/camera_service.dart';

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
                onPressed: camera.start,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('카메라 다시 켜기'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              ),
            ],
          ),
        ),
      );
    } else if (camera.ready) {
      content = camera.preview();
    } else {
      content = const Center(child: CircularProgressIndicator());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(color: const Color(0xFF111318), child: content),
    );
  }
}

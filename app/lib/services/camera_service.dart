import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/document_photo.dart';

/// 앱을 켜자마자 여는 카메라. 문서 사진을 찍을 때와 쓰기 확인용으로 다시 찍을 때 함께 쓴다.
class CameraService extends ChangeNotifier {
  CameraController? _controller;
  CameraController? get controller => _controller;

  String? _error;
  String? get error => _error;

  bool get ready => _controller?.value.isInitialized ?? false;

  Future<void> start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', '카메라 없음');
      // 문서를 비추려면 뒷면 카메라가 낫다. 노트북처럼 없으면 첫 번째 카메라를 쓴다.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();
      _controller = controller;
      _error = null;
    } catch (_) {
      _error = '카메라를 켤 수 없어요. 카메라 권한을 확인하거나 사진 불러오기를 써 주세요.';
    }
    notifyListeners();
  }

  Future<DocumentPhoto?> snapshot() async {
    final controller = _controller;
    if (controller == null || !ready) return null;
    final file = await controller.takePicture();
    return DocumentPhoto(bytes: await file.readAsBytes(), name: 'document.jpg');
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

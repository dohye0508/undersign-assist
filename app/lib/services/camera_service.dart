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

  /// 카메라를 연다. 실패하면 [error]에 이유를 남긴다. 다시 부르면 다시 시도한다.
  Future<void> start() async {
    _error = null;
    await _controller?.dispose();
    _controller = null;
    notifyListeners();

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      _fail('카메라 목록을 가져오지 못했어요', e);
      return;
    }
    if (cameras.isEmpty) {
      _fail('연결된 카메라가 없어요', null);
      return;
    }
    // 문서를 비추려면 뒷면 카메라가 낫다. 노트북처럼 없으면 첫 번째 카메라를 쓴다.
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    // 노트북 카메라는 높은 해상도를 지원하지 않으면 열리지 않는다. 낮춰 가며 시도한다.
    Object? lastError;
    for (final preset in [ResolutionPreset.veryHigh, ResolutionPreset.high, ResolutionPreset.medium]) {
      final controller = CameraController(camera, preset, enableAudio: false);
      try {
        await controller.initialize();
        _controller = controller;
        notifyListeners();
        return;
      } catch (e) {
        lastError = e;
        debugPrint('카메라 $preset 실패: $e');
        await controller.dispose();
      }
    }
    _fail('카메라를 켤 수 없어요', lastError);
  }

  void _fail(String message, Object? cause) {
    debugPrint('$message: $cause');
    final detail = switch (cause) {
      CameraException(:final code, :final description) => ' ($code${description == null ? '' : ': $description'})',
      null => '',
      _ => ' ($cause)',
    };
    _error = '$message. 다른 프로그램이 카메라를 쓰고 있지 않은지 확인하고 다시 켜 보세요.$detail';
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

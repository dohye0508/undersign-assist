import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/document_photo.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';

/// 종이 문서를 찍는 화면. 찍은 사진을 [DocumentPhoto]로 돌려준다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', '카메라 없음');
      // 문서를 비추려면 뒷면 카메라가 낫다. 노트북처럼 없으면 첫 번째 카메라를 쓴다.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) return controller.dispose();
      setState(() => _controller = controller);
      Speech.announce(context, '카메라를 켰어요. 종이 문서를 카메라 앞에 놓고 찍기 버튼을 누르세요.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '카메라를 켤 수 없어요. 카메라 권한을 확인하거나 사진 불러오기를 써 주세요.');
      Speech.announce(context, _error!);
    }
  }

  // TODO: 문서 네 귀퉁이가 화면 안에 들어왔는지 확인하고 방향을 음성으로 안내하기

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null) return;
    final file = await controller.takePicture();
    final photo = DocumentPhoto(bytes: await file.readAsBytes(), name: 'document.jpg');
    if (mounted) Navigator.of(context).pop(photo);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('카메라로 찍기')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: Theme.of(context).textTheme.bodyLarge),
                      )
                    : controller == null
                        ? const CircularProgressIndicator(color: AppColors.amber)
                        : CameraPreview(controller),
              ),
            ),
            const SizedBox(height: 24),
            BigButton(
              label: '찍기',
              icon: Icons.camera,
              hint: '지금 보이는 문서를 찍어요',
              onPressed: controller == null ? null : _capture,
            ),
          ],
        ),
      ),
    );
  }
}

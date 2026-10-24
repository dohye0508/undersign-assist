import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/document_photo.dart';
import '../models/document_session.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import 'camera_screen.dart';
import 'document_screen.dart';

/// 첫 화면. 종이 문서 사진을 받는 두 가지 방법만 보여준다.
/// 사진이 정해진 뒤에야 읽기, 판단, 쓰기, 서명 화면으로 넘어간다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _fromCamera(BuildContext context) async {
    final photo = await Navigator.of(context).push<DocumentPhoto>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (photo != null && context.mounted) _openDocument(context, photo);
  }

  Future<void> _fromFolder(BuildContext context) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final photo = DocumentPhoto(bytes: await file.readAsBytes(), name: file.name);
    if (context.mounted) _openDocument(context, photo);
  }

  void _openDocument(BuildContext context, DocumentPhoto photo) {
    Speech.announce(context, '사진을 받았어요. 문서를 읽을게요.');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocumentScreen(session: DocumentSession(photo))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text('undersign', style: text.displaySmall, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '종이 문서를 보여주세요.\n읽고, 판단하고, 쓰고, 서명하는 것까지 함께할게요.',
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  BigButton(
                    label: '카메라로 찍기',
                    icon: Icons.photo_camera_outlined,
                    hint: '종이 문서를 카메라로 찍어요',
                    onPressed: () => _fromCamera(context),
                  ),
                  const SizedBox(height: 20),
                  BigButton(
                    label: '사진 불러오기',
                    icon: Icons.folder_open_outlined,
                    hint: '폴더에 있는 문서 사진을 골라요',
                    onPressed: () => _fromFolder(context),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '사진은 서버에 저장하지 않아요.',
                    style: text.bodyMedium?.copyWith(fontSize: 16, color: AppColors.line),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

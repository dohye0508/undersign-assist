import 'package:flutter/material.dart';

import '../../models/document_photo.dart';
import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/api_client.dart';
import '../../services/camera_service.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 쓰기: 칸을 고르고 종이에 펜으로 쓴 뒤 찍으면, 그 칸에 무엇이 쓰였는지 읽어준다.
class WriteMode {
  WriteMode._();

  /// 서식에 흔한 칸 이름. 읽은 문서가 있으면 그 문서에 있는 것만 보여준다
  static const commonFields = ['성명', '주소', '연락처', '생년월일', '날짜'];

  static final field = ValueNotifier<String>(commonFields.first);

  static List<String> fieldsFor(RecognizedDocument? document) {
    final text = (document?.fullText ?? '').replaceAll(RegExp(r'\s'), '');
    final found = commonFields.where(text.contains).toList();
    return found.isEmpty ? commonFields : found;
  }

  /// 사진에서 고른 칸을 확인하고, 들려줄 문장을 돌려준다
  static Future<String> check(DocumentPhoto photo) async {
    try {
      final result = await ApiClient.checkWriting(photo, field.value);
      return result['speech'] as String? ?? '';
    } catch (_) {
      return '글씨를 확인하지 못했어요. 다시 찍어 주세요.';
    }
  }
}

/// 쓰기 단계 화면. 분석 화면에서는 큰 카메라가 없으므로, 종이를 맞춰 놓을 수 있게 작은 카메라를 함께 보여준다.
class WritePanel extends StatefulWidget {
  const WritePanel({super.key, required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  State<WritePanel> createState() => _WritePanelState();
}

class _WritePanelState extends State<WritePanel> {
  bool _busy = false;
  String? _result;

  Future<void> _check() async {
    setState(() => _busy = true);
    Speech.announce(context, '${WriteMode.field.value} 칸을 확인하고 있어요.');
    // 쓴 뒤의 종이를 새로 찍는다. 카메라가 없으면 첫 페이지 사진으로 확인한다
    final photo = await widget.camera.snapshot() ?? widget.state.pages.first;
    final message = await WriteMode.check(photo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
    });
    Speech.announce(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: WorkStep.write.label,
      description: '칸을 고르고, 종이에 쓴 다음 카메라 앞에 놓고 확인을 누르세요.',
      children: [
        if (widget.camera.ready)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: 4 / 3, child: widget.camera.preview()),
          ),
        const SizedBox(height: 14),
        WriteFieldPicker(document: widget.state.recognized),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(_busy ? '확인하는 중…' : '찍어서 확인'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 16),
          WriteResultView(message: _result!),
        ],
      ],
    );
  }
}

/// 칸 고르기 줄
class WriteFieldPicker extends StatelessWidget {
  const WriteFieldPicker({super.key, required this.document});

  final RecognizedDocument? document;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: WriteMode.field,
      builder: (context, selected, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final field in WriteMode.fieldsFor(document)) ...[
              ChoiceChip(
                label: Text(field, style: const TextStyle(fontSize: 17)),
                selected: field == selected,
                onSelected: (_) {
                  WriteMode.field.value = field;
                  Speech.announce(context, '$field 칸. 종이에 쓰고 찍으세요.');
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// 결과 창에 보이는 쓰기 결과
class WriteResultView extends StatelessWidget {
  const WriteResultView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 22)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Speech.announce(context, message),
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('다시 듣기'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
      ],
    );
  }
}

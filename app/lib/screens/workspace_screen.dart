import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../features/judge/judge_panel.dart';
import '../features/read/read_panel.dart';
import '../features/sign/sign_panel.dart';
import '../features/write/write_panel.dart';
import '../models/document_photo.dart';
import '../models/workspace_state.dart';
import '../services/camera_service.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/document_stage.dart';

/// 앱의 유일한 화면.
/// 왼쪽(좁은 화면에서는 위): 켜자마자 나오는 카메라, 사진을 받으면 그 사진.
/// 오른쪽(좁은 화면에서는 아래): 찍기와 사진 불러오기, 그 아래 네 단계와 선택한 단계의 내용.
///
/// 키보드: C 찍기, O 사진 불러오기, 1~4 단계 선택, Esc 다시 찍기
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _state = WorkspaceState();
  final _camera = CameraService();

  @override
  void initState() {
    super.initState();
    _camera.start().then((_) {
      if (!mounted) return;
      Speech.announce(
        context,
        _camera.error ?? '카메라를 켰어요. 문서를 카메라 앞에 놓고 찍기를 누르세요. 키보드 C를 눌러도 찍혀요.',
      );
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final photo = await _camera.snapshot();
    if (photo == null) {
      if (mounted) Speech.announce(context, '카메라가 준비되지 않았어요. 사진 불러오기를 써 주세요.');
      return;
    }
    await _usePhoto(photo);
  }

  Future<void> _pickFromFolder() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _usePhoto(DocumentPhoto(bytes: await file.readAsBytes(), name: file.name));
  }

  Future<void> _usePhoto(DocumentPhoto photo) async {
    Speech.announce(context, '사진을 받았어요. 문서를 읽고 있어요.');
    final document = await _state.setPhoto(photo);
    if (!mounted) return;
    Speech.announce(context, document?.speech ?? _state.readError ?? '');
  }

  void _retake() {
    _state.clearPhoto();
    Speech.announce(context, '사진을 지웠어요. 다시 찍을 수 있어요.');
  }

  void _selectStep(WorkStep step) {
    if (!_state.hasPhoto) {
      Speech.announce(context, '먼저 문서를 찍거나 불러와 주세요.');
      return;
    }
    _state.selectStep(step);
    Speech.announce(context, '${step.label}. ${step.summary}');
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC): _capture,
        const SingleActivator(LogicalKeyboardKey.keyO): _pickFromFolder,
        const SingleActivator(LogicalKeyboardKey.escape): _retake,
        for (final (i, step) in WorkStep.values.indexed)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () => _selectStep(step),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppColors.pageGradient),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: Listenable.merge([_state, _camera]),
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final stage = DocumentStage(state: _state, camera: _camera);
                    final wide = constraints.maxWidth >= 900;
                    final panel = _SidePanel(
                      scrollable: wide,
                      state: _state,
                      camera: _camera,
                      onCapture: _capture,
                      onPick: _pickFromFolder,
                      onRetake: _retake,
                      onSelectStep: _selectStep,
                    );

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: Padding(padding: const EdgeInsets.all(20), child: stage)),
                          SizedBox(width: 420, child: panel),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: AspectRatio(aspectRatio: 3 / 4, child: stage),
                        ),
                        panel,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.scrollable,
    required this.state,
    required this.camera,
    required this.onCapture,
    required this.onPick,
    required this.onRetake,
    required this.onSelectStep,
  });

  /// 넓은 화면에서는 패널이 따로 스크롤되고, 좁은 화면에서는 페이지 전체와 함께 스크롤된다
  final bool scrollable;
  final WorkspaceState state;
  final CameraService camera;
  final VoidCallback onCapture;
  final VoidCallback onPick;
  final VoidCallback onRetake;
  final ValueChanged<WorkStep> onSelectStep;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      color: AppColors.surface.withValues(alpha: 0.85),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        shrinkWrap: !scrollable,
        primary: false,
        physics: scrollable ? null : const NeverScrollableScrollPhysics(),
        children: [
          Semantics(header: true, child: Text('undersign', style: text.headlineMedium)),
          const SizedBox(height: 4),
          Text('종이 문서를 읽고, 판단하고, 쓰고, 서명하는 것을 도와드려요.', style: text.bodyMedium),
          const SizedBox(height: 24),

          // 문서 사진 받기
          if (!state.hasPhoto)
            FilledButton.icon(
              onPressed: camera.ready ? onCapture : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('찍기  (C)'),
            )
          else
            FilledButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 찍기  (Esc)'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('사진 불러오기  (O)'),
          ),
          const SizedBox(height: 32),

          // 네 단계
          Text('단계', style: text.labelLarge),
          const SizedBox(height: 8),
          for (final (i, step) in WorkStep.values.indexed)
            _StepTile(
              number: i + 1,
              step: step,
              selected: state.hasPhoto && state.step == step,
              enabled: state.hasPhoto,
              onTap: () => onSelectStep(step),
            ),
          const SizedBox(height: 24),

          // 선택한 단계의 내용
          if (state.hasPhoto)
            switch (state.step) {
              WorkStep.read => ReadPanel(state: state),
              WorkStep.judge => JudgePanel(state: state),
              WorkStep.write => WritePanel(state: state, camera: camera),
              WorkStep.sign => SignPanel(state: state),
            }
          else
            Text('문서를 찍거나 불러오면 단계를 고를 수 있어요.', style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.step,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int number;
  final WorkStep step;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        child: ListTile(
          enabled: enabled,
          selected: selected,
          onTap: onTap,
          minTileHeight: 60,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          selectedTileColor: AppColors.primarySoft,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: selected ? AppColors.primary : AppColors.line,
            foregroundColor: selected ? Colors.white : AppColors.muted,
            child: Text('$number'),
          ),
          title: Text(step.label, style: const TextStyle(fontSize: 20)),
          subtitle: Text(step.summary),
        ),
      ),
    );
  }
}

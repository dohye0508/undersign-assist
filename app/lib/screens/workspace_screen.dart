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
import '../widgets/panel_section.dart';
import '../widgets/voice_guide_card.dart';

/// 앱의 유일한 화면. 노트북에서 시연하므로 가로로 나눈다.
/// 왼쪽: 켜자마자 나오는 카메라 (사진을 받으면 그 사진).
/// 오른쪽: 음성 안내, 촬영하기와 파일 선택, 네 단계, 고른 단계의 내용.
///
/// 키보드: C 촬영, O 파일 선택, 1~4 단계 선택, Esc 다시 촬영
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
      Speech.announce(context, _camera.error ?? '문서를 카메라 앞에 평평하게 놓고 촬영하기를 누르세요. 키보드 C를 눌러도 돼요.');
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
      if (mounted) Speech.announce(context, '카메라가 준비되지 않았어요. 파일 선택으로 사진을 불러와 주세요.');
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
    Speech.announce(context, '사진을 지웠어요. 다시 촬영할 수 있어요.');
  }

  void _selectStep(WorkStep step) {
    if (!_state.hasPhoto) {
      Speech.announce(context, '먼저 문서를 촬영하거나 파일로 불러와 주세요.');
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
          body: SafeArea(
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
                        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(24, 24, 8, 24), child: stage)),
                        SizedBox(width: 440, child: panel),
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
    final document = state.recognized;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 24, 32),
      shrinkWrap: !scrollable,
      primary: false,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      children: [
        // 머리: 앱 이름
        Semantics(
          header: true,
          child: const Text(
            '들리는계약서',
            style: TextStyle(fontFamily: AppFonts.logo, fontSize: 32, color: AppColors.text),
          ),
        ),
        Text('종이 문서를 읽고, 판단하고, 쓰고, 서명하도록 도와드려요', style: text.bodyMedium),
        const SizedBox(height: 18),

        VoiceGuideCard(
          detail: document == null
              ? null
              : '${document.docTypeLabel} · ${document.reader == 'ai' ? 'AI로 정리' : '규칙으로 정리'}',
        ),
        const SizedBox(height: 14),

        // 문서 사진 받기 (디자인 시안의 "촬영하기 / 파일 선택" 두 버튼)
        Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: AppColors.buttonShadow),
                child: state.hasPhoto
                    ? FilledButton.icon(
                        onPressed: onRetake,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('다시 촬영'),
                      )
                    : FilledButton.icon(
                        onPressed: camera.ready ? onCapture : null,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('촬영하기'),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('파일 선택'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('키보드  C 촬영 · O 파일 · 1~4 단계 · Esc 다시', style: text.labelSmall, textAlign: TextAlign.center),
        const SizedBox(height: 22),

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
        const SizedBox(height: 22),

        // 고른 단계의 내용
        if (state.hasPhoto)
          switch (state.step) {
            WorkStep.read => ReadPanel(state: state),
            WorkStep.judge => JudgePanel(state: state),
            WorkStep.write => WritePanel(state: state, camera: camera),
            WorkStep.sign => SignPanel(state: state),
          }
        else
          AppCard(
            child: Text('문서를 촬영하거나 파일로 불러오면 바로 읽어드리고, 단계를 고를 수 있어요.', style: text.bodyMedium),
          ),
      ],
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
    final color = !enabled ? AppColors.subtle : (selected ? AppColors.primary : AppColors.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        enabled: enabled,
        child: Material(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: !enabled ? AppColors.line : (selected ? AppColors.primary : AppColors.text),
                    foregroundColor: Colors.white,
                    child: Text('$number', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Text(step.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(step.summary, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

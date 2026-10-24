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
import '../widgets/soft_blob_background.dart';

/// 앱의 유일한 화면. 켜자마자 카메라가 화면 대부분을 차지하고, 아래에는 아주 적은 버튼만 있다.
///   - 할 일 줄: 문서 읽기 / 빠진 것 확인 / 쓴 글씨 확인 / 서명 위치
///   - 맨 아래: 사진 불러오기, 큰 촬영 버튼, 다시 듣기
/// 찍으면 고른 할 일에 맞는 결과 창이 카메라 위로 올라온다. 닫으면 다시 카메라.
///
/// 키보드: Space 또는 C 촬영, O 사진 불러오기, 1~4 할 일, R 다시 듣기, Esc 결과 닫기
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _state = WorkspaceState();
  final _camera = CameraService();

  /// 결과 창에 보일 할 일. null이면 결과 창이 닫혀 있다
  WorkStep? _resultFor;
  String? _writeResult;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _camera.start().then((_) {
      if (!mounted) return;
      Speech.announce(context, _camera.error ?? '카메라가 켜졌어요. 문서를 카메라 앞에 놓고 아래 가운데 버튼을 누르세요.');
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy) return;
    final photo = await _camera.snapshot();
    if (photo == null) {
      if (mounted) Speech.announce(context, '카메라가 준비되지 않았어요. 왼쪽 아래 사진 불러오기를 써 주세요.');
      return;
    }
    await _handle(photo);
  }

  Future<void> _pickFromFolder() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _handle(DocumentPhoto(bytes: await file.readAsBytes(), name: file.name));
  }

  /// 고른 할 일에 따라 사진을 처리하고 결과 창을 연다
  Future<void> _handle(DocumentPhoto photo) async {
    final step = _state.step;
    setState(() {
      _busy = true;
      _resultFor = step;
    });

    String speech;
    if (step == WorkStep.write) {
      Speech.announce(context, '${WriteMode.field.value} 칸을 확인하고 있어요.');
      speech = await WriteMode.check(photo);
      _writeResult = speech;
    } else {
      Speech.announce(context, '문서를 읽고 있어요.');
      final document = await _state.setPhoto(photo);
      speech = switch (step) {
        WorkStep.read => document?.speech ?? _state.readError ?? '',
        // 판단, 서명은 아직 화면만 있다
        _ => '${document?.docTypeLabel ?? '문서'}를 읽었어요. ${step.label} 기능은 준비 중이에요.',
      };
    }

    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, speech);
  }

  void _closeResult() {
    if (_resultFor == null) return;
    setState(() => _resultFor = null);
    _state.clearPhoto();
    Speech.announce(context, '카메라로 돌아왔어요.');
  }

  void _selectStep(WorkStep step) {
    _state.selectStep(step);
    Speech.announce(context, '${step.label}. ${step.guide}');
  }

  void _repeat() {
    final last = Speech.lastMessage.value;
    if (last.isNotEmpty) Speech.announce(context, last);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _capture,
        const SingleActivator(LogicalKeyboardKey.keyC): _capture,
        const SingleActivator(LogicalKeyboardKey.keyO): _pickFromFolder,
        const SingleActivator(LogicalKeyboardKey.keyR): _repeat,
        const SingleActivator(LogicalKeyboardKey.escape): _closeResult,
        for (final (i, step) in WorkStep.values.indexed)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () => _selectStep(step),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: SoftBlobBackground()),
              SafeArea(
                // 노트북에서도 휴대폰 화면처럼 가운데에 세로로 둔다
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_state, _camera]),
                      builder: (context, _) => Column(
                        children: [
                          const _TopBar(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  DocumentStage(state: _state, camera: _camera),
                                  if (_resultFor != null)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _ResultSheet(onClose: _closeResult, child: _resultView()),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_state.step == WorkStep.write && _resultFor == null) ...[
                            const SizedBox(height: 10),
                            WriteFieldPicker(document: _state.recognized),
                          ],
                          const SizedBox(height: 10),
                          _ModeBar(selected: _state.step, onSelect: _selectStep),
                          _BottomBar(
                            busy: _busy,
                            canCapture: _camera.ready,
                            onPick: _pickFromFolder,
                            onCapture: _capture,
                            onRepeat: _repeat,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView() => switch (_resultFor!) {
        WorkStep.read => ReadPanel(state: _state),
        WorkStep.judge => JudgePanel(state: _state),
        WorkStep.write => _busy
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : WriteResultView(message: _writeResult ?? ''),
        WorkStep.sign => SignPanel(state: _state),
      };
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Semantics(
              header: true,
              child: Text('들리는계약서', style: Theme.of(context).textTheme.titleLarge),
            ),
            const Spacer(),
            IconButton(
              tooltip: '사용 방법',
              icon: const Icon(Icons.info_outline, color: AppColors.muted),
              onPressed: () => Speech.announce(
                context,
                '가운데 버튼으로 문서를 찍어요. 아래 줄에서 할 일을 고를 수 있어요. 키보드는 스페이스로 찍고, 1부터 4로 할 일을 고르고, R로 다시 들어요.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 할 일 고르기 줄. 고른 것은 파란 칸으로 표시한다
class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.selected, required this.onSelect});

  final WorkStep selected;
  final ValueChanged<WorkStep> onSelect;

  static const _icons = {
    WorkStep.read: Icons.description_outlined,
    WorkStep.judge: Icons.fact_check_outlined,
    WorkStep.write: Icons.edit_outlined,
    WorkStep.sign: Icons.draw_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final step in WorkStep.values)
            Expanded(
              child: Semantics(
                selected: step == selected,
                button: true,
                label: step.label,
                excludeSemantics: true,
                child: Material(
                  color: step == selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => onSelect(step),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Icon(_icons[step], color: step == selected ? Colors.white : AppColors.text),
                          const SizedBox(height: 4),
                          Text(
                            step.label,
                            style: TextStyle(fontSize: 14, color: step == selected ? Colors.white : AppColors.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 맨 아래: 사진 불러오기, 큰 촬영 버튼, 다시 듣기
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.canCapture,
    required this.onPick,
    required this.onCapture,
    required this.onRepeat,
  });

  final bool busy;
  final bool canCapture;
  final VoidCallback onPick;
  final VoidCallback onCapture;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideButton(icon: Icons.photo_library_outlined, label: '사진 불러오기', onTap: onPick),
          Semantics(
            button: true,
            label: '찍기',
            excludeSemantics: true,
            child: SizedBox(
              width: 80,
              height: 80,
              child: FilledButton(
                onPressed: canCapture && !busy ? onCapture : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(80, 80),
                ),
                child: busy
                    ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.photo_camera, size: 36),
              ),
            ),
          ),
          _SideButton(icon: Icons.volume_up_outlined, label: '다시 듣기', onTap: onRepeat),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: AppColors.text),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 찍은 뒤 카메라 위로 올라오는 결과 창
class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: '닫고 카메라로 돌아가기',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

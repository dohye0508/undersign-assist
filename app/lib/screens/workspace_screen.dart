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

/// 앱의 유일한 화면. 켜자마자 카메라가 화면 대부분을 차지하고, 아래에는 버튼 세 개만 있다
/// (사진 불러오기, 큰 촬영 버튼, 다시 듣기).
///
/// 찍으면 먼저 문서를 읽고 결과 창을 카메라 위로 올린다. 결과 창 아래쪽 "다음에 할 일"에서
/// 빠진 것 확인, 쓴 글씨 확인, 서명 위치로 넘어간다. 닫으면 다시 카메라.
///
/// 키보드: Space 또는 C 촬영, O 사진 불러오기, 1~4 할 일(문서를 읽은 뒤), R 다시 듣기, Esc 닫기
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _state = WorkspaceState();
  final _camera = CameraService();

  /// 결과 창에 보이는 할 일. null이면 결과 창이 닫혀 있다
  WorkStep? _sheet;
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
    await _read(photo);
  }

  Future<void> _pickFromFolder() async {
    if (_busy) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _read(DocumentPhoto(bytes: await file.readAsBytes(), name: file.name));
  }

  /// 새 문서는 언제나 먼저 읽는다
  Future<void> _read(DocumentPhoto photo) async {
    setState(() {
      _busy = true;
      _sheet = WorkStep.read;
      _writeResult = null;
    });
    Speech.announce(context, '문서를 읽고 있어요.');
    final document = await _state.setPhoto(photo);
    if (!mounted) return;
    setState(() => _busy = false);
    final next = document == null ? '' : ' 다음에 할 일을 고를 수 있어요.';
    Speech.announce(context, (document?.speech ?? _state.readError ?? '') + next);
  }

  /// 결과 창 안에서 다른 할 일로 넘어간다
  void _openStep(WorkStep step) {
    if (_state.recognized == null) {
      Speech.announce(context, '먼저 문서를 찍어 주세요.');
      return;
    }
    setState(() => _sheet = step);
    Speech.announce(context, '${step.label}. ${step.guide}');
  }

  /// 쓴 글씨 확인: 종이에 쓴 다음 다시 찍어서 고른 칸을 읽는다
  Future<void> _checkWriting() async {
    if (_busy) return;
    setState(() => _busy = true);
    Speech.announce(context, '${WriteMode.field.value} 칸을 확인하고 있어요.');
    final photo = await _camera.snapshot() ?? _state.photo!;
    final message = await WriteMode.check(photo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _writeResult = message;
    });
    Speech.announce(context, message);
  }

  void _close() {
    if (_sheet == null) return;
    setState(() => _sheet = null);
    _state.clearPhoto();
    Speech.announce(context, '카메라로 돌아왔어요.');
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
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        for (final (i, step) in WorkStep.values.indexed)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () => _openStep(step),
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
                                  if (_sheet != null)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: _ResultSheet(
                                        onClose: _close,
                                        onBack: _sheet == WorkStep.read ? null : () => _openStep(WorkStep.read),
                                        child: _sheetContent(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
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

  Widget _sheetContent() => switch (_sheet!) {
        WorkStep.read => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReadPanel(state: _state),
              if (_state.recognized != null) ...[
                const SizedBox(height: 24),
                _NextSteps(onOpen: _openStep),
              ],
            ],
          ),
        WorkStep.judge => JudgePanel(state: _state),
        WorkStep.write => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(WorkStep.write.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('칸을 고르고, 종이에 쓴 다음 카메라 앞에 놓고 확인을 누르세요.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              WriteFieldPicker(document: _state.recognized),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _checkWriting,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_busy ? '확인하는 중…' : '찍어서 확인'),
              ),
              if (_writeResult != null) ...[
                const SizedBox(height: 16),
                WriteResultView(message: _writeResult!),
              ],
            ],
          ),
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
                '가운데 버튼으로 문서를 찍으면 읽어드려요. 읽은 다음에는 빠진 것 확인, 쓴 글씨 확인, 서명 위치를 고를 수 있어요. 키보드는 스페이스로 찍고, R로 다시 들어요.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 문서를 읽은 뒤 결과 창 아래쪽에 나오는 다음 할 일
class _NextSteps extends StatelessWidget {
  const _NextSteps({required this.onOpen});

  final ValueChanged<WorkStep> onOpen;

  static const _icons = {
    WorkStep.judge: Icons.fact_check_outlined,
    WorkStep.write: Icons.edit_outlined,
    WorkStep.sign: Icons.draw_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('다음에 할 일', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (final step in [WorkStep.judge, WorkStep.write, WorkStep.sign]) ...[
          OutlinedButton.icon(
            onPressed: () => onOpen(step),
            icon: Icon(_icons[step]),
            label: Text(step.label),
          ),
          const SizedBox(height: 8),
        ],
      ],
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
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideButton(icon: Icons.photo_library_outlined, label: '사진 불러오기', onTap: onPick),
          Semantics(
            button: true,
            label: '찍기',
            excludeSemantics: true,
            child: SizedBox(
              width: 84,
              height: 84,
              child: FilledButton(
                onPressed: canCapture && !busy ? onCapture : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(84, 84),
                ),
                child: busy
                    ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.photo_camera, size: 38),
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
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: AppColors.text),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 14, color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 찍은 뒤 카메라 위로 올라오는 결과 창
class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.onClose, required this.child, this.onBack});

  final VoidCallback onClose;

  /// 문서 읽기 결과로 돌아가기 (다른 할 일을 보고 있을 때만)
  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onBack != null)
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('문서 읽기로'),
                ),
              const Spacer(),
              IconButton(tooltip: '닫고 카메라로 돌아가기', icon: const Icon(Icons.close), onPressed: onClose),
            ],
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

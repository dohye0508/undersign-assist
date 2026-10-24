import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../features/judge/judge_panel.dart';
import '../features/read/read_panel.dart';
import '../features/sign/sign_panel.dart';
import '../features/sign/signature_spots.dart';
import '../features/write/write_panel.dart';
import '../models/document_photo.dart';
import '../models/workspace_state.dart';
import '../services/camera_service.dart';
import '../services/haptics.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/document_stage.dart';
import '../widgets/page_tray.dart';
import '../widgets/soft_blob_background.dart';

/// 앱의 유일한 화면. 두 가지 모습이 있고 서로 "바뀐다"(덮지 않는다).
///
/// 촬영: 카메라가 화면 대부분을 차지한다. 위쪽 가운데 버튼을 누르면 찍은 페이지 목록이 내려온다.
///       아래에는 사진 불러오기, 찍기, 분석하기 세 버튼만 있다. 찍을 때마다 페이지가 하나씩 쌓인다.
/// 분석: 모든 페이지를 한 문서로 읽은 결과. 더 찍을 일이 없으므로 화면 전체를 쓴다.
///       문서 읽기 → 다음에 할 일(검토하세요!, 쓴 글씨 확인, 서명 위치).
///
/// 키보드 (촬영): Space/C 찍기, O 사진 불러오기, P 페이지 목록, Enter 분석하기
/// 키보드 (분석): Esc 카메라로, 1~4 단계
/// 키보드 (공통): R 다시 듣기
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _state = WorkspaceState();
  final _camera = CameraService();

  /// 분석 화면이면 지금 보이는 단계, 촬영 화면이면 null
  WorkStep? _step;
  bool _trayOpen = false;

  bool get _analyzing => _step != null;

  @override
  void initState() {
    super.initState();
    _camera.start().then((_) {
      if (!mounted) return;
      Speech.announce(
        context,
        _camera.error ?? '카메라가 켜졌어요. 문서를 한 장씩 카메라 앞에 놓고 아래 가운데 버튼으로 찍으세요. 다 찍으면 오른쪽 아래 분석하기를 누르세요.',
      );
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    _state.dispose();
    super.dispose();
  }

  // --- 촬영 ------------------------------------------------------------------

  Future<void> _capture() async {
    if (_analyzing) return;
    final photo = await _camera.snapshot();
    if (photo == null) {
      if (mounted) Speech.announce(context, '카메라가 준비되지 않았어요. 왼쪽 아래 사진 불러오기를 써 주세요.');
      return;
    }
    _state.addPage(photo);
    Haptics.ok();
    if (mounted) {
      final n = _state.pages.length;
      Speech.announce(context, '$n페이지를 찍었어요. 다음 장을 올리고 찍거나, 다 찍었으면 분석하기를 누르세요.');
    }
  }

  Future<void> _pickFromFolder() async {
    if (_analyzing) return;
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    for (final file in files) {
      _state.addPage(DocumentPhoto(bytes: await file.readAsBytes(), name: file.name));
    }
    if (mounted) {
      Speech.announce(context, '${files.length}장을 불러왔어요. 지금까지 모두 ${_state.pages.length}페이지예요.');
    }
  }

  void _toggleTray() {
    if (_analyzing) return;
    setState(() => _trayOpen = !_trayOpen);
    final n = _state.pages.length;
    Speech.announce(context, _trayOpen ? '찍은 페이지 $n장 목록을 열었어요.' : '목록을 닫았어요.');
  }

  void _removePage(int index) {
    _state.removePage(index);
    Speech.announce(context, '${index + 1}페이지를 지웠어요. 남은 페이지는 ${_state.pages.length}장이에요.');
  }

  void _clearPages() {
    _state.clearPages();
    Speech.announce(context, '찍은 페이지를 모두 지웠어요. 새 문서를 찍으세요.');
  }

  // --- 분석 ------------------------------------------------------------------

  Future<void> _analyze() async {
    if (_analyzing) return;
    if (!_state.hasPages) {
      Speech.announce(context, '먼저 문서를 한 장 이상 찍어 주세요.');
      return;
    }
    setState(() {
      _step = WorkStep.read;
      _trayOpen = false;
    });
    final pages = _state.pages.length;
    Speech.announce(context, '$pages페이지를 분석하고 있어요.');
    final document = await _state.read();
    if (!mounted) return;
    if (document == null) {
      Speech.announce(context, _state.readError ?? '');
      return;
    }
    // 계획서: "총 7페이지입니다. … 서명이 필요한 페이지는 1페이지와 7페이지입니다."
    final signPages = describeSignaturePages(findSignatureSpots(document));
    Speech.announce(context, '총 $pages페이지예요. ${document.speech} $signPages 다음에 할 일을 고를 수 있어요.');
  }

  void _openStep(WorkStep step) {
    if (!_analyzing) return;
    if (_state.recognized == null) {
      Speech.announce(context, '먼저 분석이 끝나야 해요.');
      return;
    }
    setState(() => _step = step);
    Speech.announce(context, '${step.label}. ${step.guide}');
  }

  void _backToCamera() {
    if (!_analyzing) return;
    setState(() => _step = null);
    Speech.announce(context, '카메라로 돌아왔어요. 찍은 페이지는 그대로 있어요.');
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
        const SingleActivator(LogicalKeyboardKey.keyP): _toggleTray,
        const SingleActivator(LogicalKeyboardKey.enter): _analyze,
        const SingleActivator(LogicalKeyboardKey.keyR): _repeat,
        const SingleActivator(LogicalKeyboardKey.escape): _backToCamera,
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
                      builder: (context, _) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        // 덮이는 느낌이 아니라 화면이 바뀌는 느낌: 옅어지며 옆에서 들어온다
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _analyzing ? _analysisView(context) : _cameraView(context),
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

  Widget _cameraView(BuildContext context) {
    return Column(
      key: const ValueKey('camera'),
      children: [
        _TopBar(
          title: '들리는계약서',
          onRepeat: _repeat,
          trailing: _state.hasPages
              ? IconButton(
                  tooltip: '모두 지우고 새 문서 찍기',
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.muted),
                  onPressed: _clearPages,
                )
              : IconButton(
                  tooltip: '사용 방법',
                  icon: const Icon(Icons.info_outline, color: AppColors.muted),
                  onPressed: () => Speech.announce(
                    context,
                    '문서를 한 장씩 찍으면 페이지가 쌓여요. 위쪽 가운데 버튼으로 찍은 페이지를 볼 수 있어요. 다 찍으면 분석하기를 누르세요. 키보드는 스페이스로 찍고, 엔터로 분석하고, R로 다시 들어요.',
                  ),
                ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DocumentStage(camera: _camera),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: PageTray(
                    pages: _state.pages,
                    open: _trayOpen,
                    onToggle: _toggleTray,
                    onRemove: _removePage,
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          canCapture: _camera.ready,
          pageCount: _state.pages.length,
          onPick: _pickFromFolder,
          onCapture: _capture,
          onAnalyze: _analyze,
        ),
      ],
    );
  }

  Widget _analysisView(BuildContext context) {
    final step = _step!;
    return Column(
      key: const ValueKey('analysis'),
      children: [
        _TopBar(
          title: '분석 결과',
          onRepeat: _repeat,
          leading: IconButton(
            tooltip: '카메라로 돌아가기',
            icon: const Icon(Icons.arrow_back),
            onPressed: _backToCamera,
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step != WorkStep.read)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openStep(WorkStep.read),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('문서 읽기로'),
                      ),
                    ),
                  switch (step) {
                    WorkStep.read => ReadPanel(state: _state),
                    WorkStep.judge => JudgePanel(state: _state),
                    WorkStep.write => WritePanel(state: _state, camera: _camera),
                    WorkStep.sign => SignPanel(state: _state),
                  },
                  if (step == WorkStep.read && _state.recognized != null) ...[
                    const SizedBox(height: 24),
                    _NextSteps(onOpen: _openStep),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onRepeat, this.leading, this.trailing});

  final String title;
  final VoidCallback onRepeat;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: EdgeInsets.only(left: leading == null ? 18 : 4, right: 6),
        child: Row(
          children: [
            ?leading,
            Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            const Spacer(),
            IconButton(
              tooltip: '다시 듣기',
              icon: const Icon(Icons.volume_up_outlined, color: AppColors.muted),
              onPressed: onRepeat,
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 문서 읽기 아래쪽에 나오는 다음 할 일
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

/// 맨 아래: 사진 불러오기, 큰 촬영 버튼, 분석하기
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canCapture,
    required this.pageCount,
    required this.onPick,
    required this.onCapture,
    required this.onAnalyze,
  });

  final bool canCapture;
  final int pageCount;
  final VoidCallback onPick;
  final VoidCallback onCapture;
  final VoidCallback onAnalyze;

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
                onPressed: canCapture ? onCapture : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(84, 84),
                ),
                child: const Icon(Icons.photo_camera, size: 38),
              ),
            ),
          ),
          _SideButton(
            icon: Icons.document_scanner_outlined,
            label: pageCount == 0 ? '분석하기' : '분석하기 ($pageCount장)',
            onTap: pageCount == 0 ? null : onAnalyze,
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.subtle : AppColors.text;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: color),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

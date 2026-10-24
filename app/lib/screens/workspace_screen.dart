import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../features/judge/judge_panel.dart';
import '../features/read/read_panel.dart';
import '../features/fill/fill_panel.dart';
import '../features/fill/fill_targets.dart';
import '../features/sign/signature_spots.dart';
import '../models/document_photo.dart';
import '../models/workspace_state.dart';
import '../services/camera_service.dart';
import '../services/haptics.dart';
import '../services/speech.dart';
import '../theme/app_theme.dart';
import '../widgets/document_stage.dart';
import '../widgets/page_tray.dart';
import '../widgets/panel_section.dart';
import '../widgets/tap_feedback.dart';

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
        _camera.error ??
            '카메라가 켜졌어요. 문서를 한 장씩 카메라 앞에 놓고 아래 가운데 버튼으로 찍으세요. 다 찍으면 오른쪽 아래 분석하기를 누르세요.',
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
      if (mounted) {
        Speech.announce(context, '카메라가 준비되지 않았어요. 왼쪽 아래 사진 불러오기를 써 주세요.');
      }
      return;
    }
    _state.addPage(photo);
    Haptics.ok();
    if (mounted) {
      final n = _state.pages.length;
      Speech.announce(
        context,
        '$n페이지를 찍었어요. 다음 장을 올리고 찍거나, 다 찍었으면 분석하기를 누르세요.',
      );
    }
  }

  Future<void> _pickFromFolder() async {
    if (_analyzing) return;
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    for (final file in files) {
      _state.addPage(
        DocumentPhoto(bytes: await file.readAsBytes(), name: file.name),
      );
    }
    if (mounted) {
      Speech.announce(
        context,
        '${files.length}장을 불러왔어요. 지금까지 모두 ${_state.pages.length}페이지예요.',
      );
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
    Speech.announce(
      context,
      '${index + 1}페이지를 지웠어요. 남은 페이지는 ${_state.pages.length}장이에요.',
    );
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
    Speech.announce(
      context,
      '총 $pages페이지예요. ${document.speech} $signPages 다음에 할 일을 고를 수 있어요.',
    );
  }

  void _openStep(WorkStep step) {
    if (!_analyzing) return;
    if (_state.recognized == null) {
      Speech.announce(context, '먼저 분석이 끝나야 해요.');
      return;
    }
    setState(() => _step = step);
    // 쓰고 서명하기는 패널이 열리며 써야 할 곳 목록을 직접 읽어준다 (겹치면 앞 말이 끊긴다)
    if (step != WorkStep.fill) Speech.announce(context, '${step.label}. ${step.guide}');
  }

  /// 한 단계씩 뒤로: 검토하세요·쓰고 서명하기 → 문서 읽기 → 카메라.
  /// 단계에서 나갈 때 바로 카메라로 가면 분석 결과를 다시 찾아야 해서 불편하다
  void _goBack() {
    if (!_analyzing) return;
    if (_step != WorkStep.read) {
      _openStep(WorkStep.read);
      return;
    }
    setState(() => _step = null);
    Speech.announce(context, '카메라로 돌아왔어요. 찍은 페이지와 분석 결과는 그대로 있어요.');
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
        const SingleActivator(LogicalKeyboardKey.escape): _goBack,
        for (final (i, step) in WorkStep.values.indexed)
          SingleActivator(
            LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
          ): () =>
              _openStep(step),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
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
                        position: Tween(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _analyzing
                        ? _analysisView(context)
                        : _cameraView(context),
                  ),
                ),
              ),
            ),
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
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: TapFeedback.wrap(_clearPages),
                )
              : IconButton(
                  tooltip: '사용 방법',
                  icon: const Icon(Icons.info_outline),
                  onPressed: TapFeedback.wrap(
                    () => Speech.announce(
                      context,
                      '문서를 한 장씩 찍으면 페이지가 쌓여요. 위쪽 가운데 버튼으로 찍은 페이지를 볼 수 있어요. 다 찍으면 분석하기를 누르세요. 키보드는 스페이스로 찍고, 엔터로 분석하고, R로 다시 들어요.',
                    ),
                  ),
                ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 카메라를 세로로 최대한 길게. 페이지 목록 버튼은 카메라 위쪽 안에 얹고, 열면 그 자리에서 내려온다
              // 페이지 목록은 카메라 윗변에 딱 붙어 있다가 그 자리에서 끌려 내려온다 (카메라 둥근 모서리로 함께 자른다)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.camera),
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
            ],
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
    final document = _state.recognized;
    return Column(
      key: const ValueKey('analysis'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackHeader(
          backLabel: step == WorkStep.read ? '카메라로' : '문서 읽기',
          tooltip: step == WorkStep.read ? '카메라로 돌아가기' : '문서 읽기로 돌아가기',
          title: step == WorkStep.read ? null : step.label,
          onBack: _goBack,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                switch (step) {
                  WorkStep.read => ReadPanel(state: _state),
                  WorkStep.judge => JudgePanel(state: _state),
                  WorkStep.fill => FillPanel(state: _state),
                },
                if (step == WorkStep.read && document != null) ...[
                  const SectionHeading('다음에 할 일'),
                  NextStepButton(
                    title: WorkStep.judge.label,
                    subtitle: '빠진 것·불리한 것 먼저 확인',
                    primary: true,
                    onPressed: () => _openStep(WorkStep.judge),
                  ),
                  const SizedBox(height: 10),
                  NextStepButton(
                    title: WorkStep.fill.label,
                    subtitle: _fillSubtitle(findFillTargets(document).length),
                    onPressed: () => _openStep(WorkStep.fill),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _fillSubtitle(int n) => n == 0 ? '써야 할 칸을 찾지 못했어요' : '써야 할 칸 $n곳';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onRepeat, this.trailing});

  final String title;
  final VoidCallback onRepeat;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const Spacer(),
          IconButton(
            tooltip: '다시 듣기',
            icon: const Icon(Icons.volume_up_rounded),
            onPressed: TapFeedback.wrap(onRepeat),
          ),
          if (trailing case final trailing?) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}

/// 분석 화면 맨 위: "‹ 카메라로" 같은 뒤로 버튼과 단계 이름
class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.backLabel, required this.tooltip, required this.onBack, this.title});

  final String backLabel;
  final String tooltip;
  final String? title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: tooltip,
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: TapFeedback.wrap(onBack),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.text,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 15, fontWeight: FontWeight.w600),
                iconSize: 20,
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              label: Text(backLabel),
            ),
          ),
          if (title case final title?)
            Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ],
      ),
    );
  }
}

/// 맨 아래: 사진 불러오기, 큰 촬영 버튼, 분석하기.
/// 양옆은 상자 없이 동그란 아이콘 + 아래 글자 (예전 모양을 토스 색으로). 분석하기만 파란 동그라미
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _SideButton(
              icon: Icons.photo_library_outlined,
              label: '사진 불러오기',
              onTap: onPick,
            ),
          ),
          Semantics(
            button: true,
            label: '찍기',
            excludeSemantics: true,
            child: InkWell(
              onTap: TapFeedback.wrap(canCapture ? onCapture : null),
              customBorder: const CircleBorder(),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: canCapture ? AppColors.primary : AppColors.grey300,
                  border: Border.all(color: AppColors.primarySoft, width: 6),
                ),
              ),
            ),
          ),
          Expanded(
            child: _SideButton(
              icon: Icons.document_scanner_outlined,
              label: pageCount == 0 ? '분석하기' : '분석하기 ($pageCount장)',
              primary: true,
              onTap: pageCount == 0 ? null : onAnalyze,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 아이콘 동그라미를 강조색으로 채운다 (분석하기)
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final circle = !enabled ? AppColors.grey100 : primary ? AppColors.primary : AppColors.grey100;
    final iconColor = !enabled ? AppColors.subtle : primary ? Colors.white : AppColors.textStrong;
    final textColor = !enabled ? AppColors.subtle : primary ? AppColors.primary : AppColors.textStrong;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: TapFeedback.wrap(onTap),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: circle),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

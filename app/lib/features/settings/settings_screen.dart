import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import '../../widgets/tap_feedback.dart';
import '../practice/practice_frame.dart';
import '../practice/practice_home.dart';
import 'app_settings.dart';
import 'device_settings.dart';

/// 사용 방법 (촬영 화면의 정보 버튼이 하던 말을 옮겼다)
const usageSpeech = '문서를 한 장씩 찍으면 페이지가 쌓여요. 카메라 위쪽 가운데 찍은 페이지 버튼을 누르면 찍은 페이지를 보고 지울 수 있어요. '
    '다 찍으면 오른쪽 아래 분석하기를 누르세요. 분석이 끝나면 검토하세요와 쓰고 서명하기로 이어져요. '
    '오른쪽 위 설정에서는 말하기 속도와 소리 크기를 바꾸고, 들리는 받아쓰기로 글씨를 연습할 수 있어요.';

/// 설정: 글씨 연습(들리는 받아쓰기), 소리(말하기 속도, 말소리 크기, 효과음 크기, 진동), 도움말.
/// 촬영 화면 오른쪽 위 설정 버튼으로 연다. Esc 또는 "‹ 카메라로"로 닫는다.
/// 값은 이 기기 브라우저 저장소에 남고([AppSettings]), 바꾸는 즉시 음성과 효과음에 적용된다.
/// 한 층으로만 둔다: 카드 안 카드 없이 행 하나가 버튼이고, 단계는 아래에서 올라오는 선택 창에서 고른다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get _s => sharedAppSettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Speech.announce(context, _intro);
    });
  }

  String get _intro => '설정이에요. 들리는 받아쓰기, 말하기 속도, 말소리 크기, 효과음 크기, 진동, 도움말이 있어요. ${_s.summarySpeech()}';

  void _close() => Navigator.of(context).maybePop();

  /// 한 번만 눌러도 바로 들어간다 (사용자 요청으로 두 번 누르기 확인을 없앴다)
  Future<void> _openPractice() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => const PracticeFlow(exitLabel: '설정으로'),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;
    Speech.announce(context, '설정으로 돌아왔어요.');
  }

  Future<void> _setRate(SettingLevel level) async {
    await updateAppSettings((s) => s.speechRate = level);
    if (!mounted) return;
    // 고른 속도로 바로 들려준다
    Speech.announce(context, '말하기 속도를 ${level.label}로 바꿨어요. 이 속도로 말해요.');
  }

  Future<void> _setSpeechVolume(SettingLevel level) async {
    await updateAppSettings((s) => s.speechVolume = level);
    if (!mounted) return;
    Speech.announce(context, '말소리 크기를 ${level.label}로 바꿨어요. 이 크기로 말해요.');
  }

  Future<void> _setEffectVolume(SettingLevel level) async {
    await updateAppSettings((s) => s.effectVolume = level);
    // 고른 크기로 딸깍 한 번 (버튼 소리를 바꾼 뒤에 낸다. 그래서 효과음 선택지는 TapFeedback으로 감싸지 않는다)
    Haptics.tap();
    if (!mounted) return;
    Speech.announce(
      context,
      level.value == 0 ? '효과음을 껐어요. 진동과 음성은 그대로 나와요.' : '효과음 크기를 ${level.label}로 바꿨어요. 이 크기로 딸깍 소리가 나요.',
    );
  }

  Future<void> _setVibrate(bool on) async {
    await updateAppSettings((s) => s.vibrate = on);
    // 켰을 때 바로 한 번 느껴 보게 한다
    if (on) Haptics.ok();
    if (!mounted) return;
    Speech.announce(context, on ? '진동을 켰어요. 안드로이드 크롬에서만 진동이 나요.' : '진동을 껐어요. 받아쓰기 안내 진동도 함께 꺼져요.');
  }

  /// 아래에서 올라오는 선택 창. 열리면 선택지를 읽어 주고, 고르면 바로 적용하고 닫는다.
  /// [tapSound]를 끄면 선택지 버튼이 딸깍을 내지 않는다(효과음 크기는 바꾼 뒤에 새 크기로 한 번 낸다).
  Future<void> _pickLevel({
    required String title,
    required List<SettingLevel> levels,
    required SettingLevel selected,
    required ValueChanged<SettingLevel> onSelect,
    bool tapSound = true,
  }) async {
    final names = levels.map((l) => l.label).join(', ');
    Speech.announce(context, '$title. $names 중에서 고르세요. 지금은 ${selected.label}예요.');
    final picked = await showModalBottomSheet<SettingLevel>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.camera)),
      ),
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (sheetContext) => _LevelSheet(title: title, levels: levels, selected: selected, tapSound: tapSound),
    );
    if (picked == null || !mounted) return;
    onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    return PracticeFrame(
      title: '',
      backLabel: '카메라로',
      onBack: _close,
      child: ListenableBuilder(
        listenable: _s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Semantics(header: true, child: Text('설정', style: Theme.of(context).textTheme.headlineMedium)),
            const SectionHeading('글씨 연습'),
            // 가장 중요한 기능이라 하늘색으로 강조한다 (분석 화면의 "다음에 할 일"과 같은 모양)
            NextStepButton(
              title: '들리는 받아쓰기',
              subtitle: '자음·모음·글자·낱말 글씨 연습',
              primary: true,
              onPressed: _openPractice,
            ),
            const SectionHeading('소리'),
            _ValueRow(
              title: '말하기 속도',
              subtitle: '읽어 주는 목소리의 빠르기',
              value: _s.speechRate.label,
              onTap: () => _pickLevel(
                title: '말하기 속도',
                levels: speechRates,
                selected: _s.speechRate,
                onSelect: _setRate,
              ),
            ),
            _ValueRow(
              title: '말소리 크기',
              subtitle: '읽어 주는 목소리의 크기',
              value: _s.speechVolume.label,
              onTap: () => _pickLevel(
                title: '말소리 크기',
                levels: speechVolumes,
                selected: _s.speechVolume,
                onSelect: _setSpeechVolume,
              ),
            ),
            _ValueRow(
              title: '효과음 크기',
              subtitle: '버튼 딸깍, 맞음·틀림 소리',
              value: _s.effectVolume.label,
              onTap: () => _pickLevel(
                title: '효과음 크기',
                levels: effectVolumes,
                selected: _s.effectVolume,
                onSelect: _setEffectVolume,
                tapSound: false,
              ),
            ),
            _SwitchRow(
              title: '진동',
              subtitle: '안드로이드 크롬에서만 나요. 받아쓰기 안내 진동도 함께',
              value: _s.vibrate,
              onChanged: _setVibrate,
            ),
            const SectionHeading('도움말'),
            _NavRow(
              title: '사용 방법 듣기',
              subtitle: '찍기부터 서명까지 순서',
              icon: Icons.volume_up_rounded,
              onTap: () => Speech.announce(context, usageSpeech),
            ),
          ],
        ),
      ),
    );
  }
}

/// 목록 행의 왼쪽: 이름 + 작은 설명
class _RowText extends StatelessWidget {
  const _RowText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
      ],
    );
  }
}

/// 누르면 어딘가로 가거나 말하는 행: 왼쪽 이름·설명, 오른쪽 › 또는 스피커
class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.subtitle, required this.icon, required this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: TapFeedback.wrap(onTap),
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _RowText(title: title, subtitle: subtitle)),
                Icon(icon, size: 26, color: AppColors.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 값 고르기 행: 왼쪽 이름·설명, 오른쪽에 지금 값 글씨만. 행 전체가 버튼이고 누르면 선택 창이 올라온다.
/// 스크린리더에는 "말하기 속도. 지금은 빠르게. 누르면 고를 수 있어요"로 읽힌다
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.title, required this.subtitle, required this.value, required this.onTap});

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. 지금은 $value. 누르면 고를 수 있어요',
      excludeSemantics: true,
      child: InkWell(
        onTap: TapFeedback.wrap(onTap),
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _RowText(title: title, subtitle: subtitle)),
                const SizedBox(width: 12),
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.accent)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 26, color: AppColors.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래에서 올라오는 선택 창: 제목과 선택지를 세로로 큰 버튼(높이 64)으로 나열.
/// 지금 값은 하늘색 바탕 + 남색 글씨 + 체크, 나머지는 회색 바탕. 고르면 그 값을 돌려주며 닫힌다
class _LevelSheet extends StatelessWidget {
  const _LevelSheet({required this.title, required this.levels, required this.selected, required this.tapSound});

  final String title;
  final List<SettingLevel> levels;
  final SettingLevel selected;
  final bool tapSound;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 14),
            for (final (i, level) in levels.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _LevelOption(
                label: level.label,
                semanticsLabel: '$title ${level.label}',
                selected: level.id == selected.id,
                onTap: () {
                  if (tapSound) Haptics.tap();
                  Navigator.of(context).pop(level);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelOption extends StatelessWidget {
  const _LevelOption({required this.label, required this.semanticsLabel, required this.selected, required this.onTap});

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.button);
    final fg = selected ? AppColors.onPrimary : AppColors.textStrong;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.primary : AppColors.grey100,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                  ),
                  if (selected) Icon(Icons.check_rounded, size: 26, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 켜기/끄기 행: 행 어디를 눌러도 바뀐다
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final toggle = TapFeedback.wrap(() => onChanged(!value));
    return Semantics(
      label: '$title. $subtitle',
      toggled: value,
      button: true,
      excludeSemantics: true,
      onTap: toggle,
      child: InkWell(
        onTap: toggle,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _RowText(title: title, subtitle: subtitle)),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  activeThumbColor: AppColors.onPrimary,
                  activeTrackColor: AppColors.primary,
                  onChanged: (_) => toggle?.call(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/judgement.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../read/read_panel.dart' show ListenButton;

/// 판단("검토하세요!"): 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다.
/// 문서만으로 알 수 없는 것(예: 사업장 인원)은 질문으로 묻고, 답을 고르면 그 답으로 다시 판단한다.
/// 판정은 백엔드 규칙 엔진(backend/app/services/judge)이 한다. 이 화면은 결과를 보여주고 읽어주기만 한다.
class JudgePanel extends StatefulWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<JudgePanel> createState() => _JudgePanelState();
}

class _JudgePanelState extends State<JudgePanel> {
  /// 질문에 답한 뒤 이전 결과와 비교한 내용. 답하기 전에는 null
  _JudgeDiff? _diff;

  @override
  void initState() {
    super.initState();
    // 창이 열리면 바로 판단하고 요약을 들려준다
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final judgement = await widget.state.judge();
      if (!mounted) return;
      Speech.announce(context, judgement?.speech ?? widget.state.judgeError ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final judgement = state.judgement;
    final text = Theme.of(context).textTheme;

    final List<Widget> body;
    if (state.judging || (judgement == null && state.judgeError == null)) {
      body = [const LinearProgressIndicator(), const SizedBox(height: 8), const Text('규칙과 법 조항으로 검토하고 있어요…')];
    } else if (judgement == null) {
      body = [
        Text(state.judgeError!),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: state.judge, child: const Text('다시 검토하기')),
      ];
    } else {
      final caution = judgement.counts['caution'] ?? 0;
      final missing = judgement.counts['missing'] ?? 0;
      // 예전 서버 응답에 남아 있을 수 있는 문장은 화면에서 뺀다
      final notice = judgement.disclaimer.replaceAll('최종 판단은 직접 하세요.', '').trim();
      final diff = _diff;
      body = [
        Text('확인이 필요한 곳 $caution개 · 빠진 항목 $missing개', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final question in judgement.questions)
          _QuestionCard(
            question: question,
            chosen: state.answers[question.id],
            onChoose: (code) => _answer(question, code),
          ),
        if (diff != null) _DiffBanner(text: diff.text),
        for (final finding in _ordered(judgement.findings))
          _FindingCard(finding: finding, change: diff?.changeOf(finding)),
        if (judgement.findings.isEmpty) Text('특별히 확인이 필요한 항목을 찾지 못했어요.', style: text.bodyLarge),
        if (notice.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(notice, style: text.bodyMedium),
        ],
      ];
    }

    // 제목은 상단 바에 이미 있으므로 여기서는 내용만 그린다
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 문서 읽기와 같이, 듣기 버튼은 맨 위에 크게
        if (judgement != null) ...[
          ListenButton(
            label: '검토 결과 듣기',
            icon: Icons.volume_up_outlined,
            primary: true,
            onPressed: () => Speech.announce(context, judgement.speech),
          ),
          const SizedBox(height: 16),
        ],
        ...body,
      ],
    );
  }

  /// 고른 답을 바로 읽어주고, 그 답으로 다시 판단한 뒤 무엇이 바뀌었는지와 새 요약을 들려준다
  Future<void> _answer(Question question, String code) async {
    final label = question.options[code] ?? code;
    // 같은 답을 다시 누르면 다시 판단하지 않고 고른 답만 알려준다
    if (widget.state.answers[question.id] == code) {
      Speech.announce(context, '고른 답: $label.');
      return;
    }
    Speech.announce(context, '고른 답: $label. 다시 검토할게요.');
    final before = widget.state.judgement;
    final judgement = await widget.state.answer(question.id, code);
    if (!mounted) return;
    if (judgement == null) {
      Speech.announce(context, widget.state.judgeError ?? '');
      return;
    }
    final diff = _JudgeDiff.compare(before, judgement);
    setState(() => _diff = diff);
    // 배너를 먼저, 요약을 그 다음에 한 번에 읽어서 중간에 끊기지 않게 한다
    Speech.announce(context, '${diff.text} 요약: ${judgement.speech}');
  }

  /// 확인 필요(심각한 것부터) → 빠짐 → 알아두기 순서
  static List<Finding> _ordered(List<Finding> findings) {
    const level = {'caution': 0, 'missing': 1, 'info': 2, 'ok': 3};
    const severity = {'critical': 0, 'high': 1, 'medium': 2, 'info': 3};
    return [...findings]
      ..sort((a, b) {
        final byLevel = (level[a.level] ?? 9).compareTo(level[b.level] ?? 9);
        return byLevel != 0 ? byLevel : (severity[a.severity] ?? 9).compareTo(severity[b.severity] ?? 9);
      });
  }
}

/// 결과 항목 하나가 이전과 비교해 어떻게 달라졌는지
enum _Change { added, changed }

/// 답을 반영하기 전후의 판단 결과 비교. 항목은 ruleId(없으면 item)로 맞춘다
class _JudgeDiff {
  const _JudgeDiff({required this.added, required this.removed, required this.changed, required this.text});

  final List<Finding> added;
  final List<Finding> removed;

  /// 같은 항목인데 수준(level)이 바뀐 것. 새 결과 기준
  final List<Finding> changed;

  /// 화면 배너와 음성에 쓰는 한 줄 설명
  final String text;

  static String _key(Finding f) => f.ruleId.isNotEmpty ? f.ruleId : f.item;

  /// 중요한 항목(확인 필요·빠짐)만 센다. 확인됨/알아두기가 오가는 것은 소리내어 알리지 않는다
  static bool _matters(Finding f) => f.level == 'caution' || f.level == 'missing';

  static _JudgeDiff compare(Judgement? before, Judgement after) {
    final old = {for (final f in before?.findings ?? const <Finding>[]) _key(f): f};
    final now = {for (final f in after.findings) _key(f): f};

    final added = <Finding>[], changed = <Finding>[], removed = <Finding>[];
    for (final entry in now.entries) {
      final previous = old[entry.key];
      if (previous == null) {
        if (_matters(entry.value)) added.add(entry.value);
      } else if (previous.level != entry.value.level && (_matters(previous) || _matters(entry.value))) {
        changed.add(entry.value);
      }
    }
    for (final entry in old.entries) {
      if (!now.containsKey(entry.key) && _matters(entry.value)) removed.add(entry.value);
    }

    final parts = <String>[
      if (removed.isNotEmpty) '확인이 필요한 곳 ${removed.length}개가 사라졌고',
      if (added.isNotEmpty) '새로 ${added.length}개가 생겼고',
      if (changed.isNotEmpty) '${changed.length}개의 결과가 바뀌었고',
    ];
    final String text;
    if (parts.isEmpty) {
      text = '답을 반영했어요. 바뀐 결과는 없어요.';
    } else {
      final names = [...added, ...changed].map((f) => f.item).where((s) => s.isNotEmpty).toList();
      final tail = names.isEmpty ? '' : ': ${names.join(', ')}';
      // 마지막 조각은 "~고" 대신 "~어요"로 끝낸다
      final last = parts.removeLast().replaceFirst(RegExp(r'고$'), '어요');
      text = '답을 반영했어요. ${[...parts, last].join(', ')}$tail.';
    }
    return _JudgeDiff(added: added, removed: removed, changed: changed, text: text);
  }

  _Change? changeOf(Finding f) {
    final key = _key(f);
    if (added.any((a) => _key(a) == key)) return _Change.added;
    if (changed.any((c) => _key(c) == key)) return _Change.changed;
    return null;
  }
}

/// 답을 반영한 뒤 무엇이 바뀌었는지 알려주는 작은 띠
class _DiffBanner extends StatelessWidget {
  const _DiffBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.autorenew, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: AppColors.primary, fontSize: 15, height: 1.35))),
          ],
        ),
      ),
    );
  }
}

enum _Kind {
  ok('확인됨', Icons.check_circle_outline, AppColors.ok, AppColors.okSoft),
  missing('빠짐', Icons.help_outline, AppColors.missing, AppColors.missingSoft),
  caution('확인 필요', Icons.error_outline, AppColors.caution, AppColors.cautionSoft),
  info('알아두기', Icons.info_outline, AppColors.primary, AppColors.primarySoft);

  const _Kind(this.label, this.icon, this.color, this.background);
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  static _Kind of(String level) => values.firstWhere((k) => k.name == level, orElse: () => info);
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, this.change});

  final Finding finding;

  /// 답을 반영한 뒤 새로 생겼거나 바뀐 항목이면 표시
  final _Change? change;

  @override
  Widget build(BuildContext context) {
    final kind = _Kind.of(finding.level);
    final sentence = finding.speech.isNotEmpty ? finding.speech : finding.reason;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      decoration: BoxDecoration(color: kind.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 첫 줄: 아이콘 + 제목 (+ 새로/바뀜 표시)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(kind.icon, color: kind.color, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${kind.label} · ${finding.item}', style: TextStyle(color: kind.color, fontSize: 18)),
                    ),
                    if (change != null) ...[
                      const SizedBox(width: 6),
                      _ChangePill(change: change!),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // 본문은 카드 왼쪽 여백에서 바로 시작한다
                Text(sentence, style: const TextStyle(color: AppColors.text, fontSize: 16.5, height: 1.35)),
                if (finding.basis.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '근거: ${finding.basis.map((b) => b.label).join(', ')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 14.5, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Speech.announce(context, _detail(finding)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.volume_up_outlined, size: 18),
              label: const Text('근거 듣기'),
            ),
          ),
        ],
      ),
    );
  }

  /// 결과 문장, 비교한 기준, 법 조항 이름을 차례로 읽어준다
  static String _detail(Finding f) => [
        f.speech,
        if (f.reason.isNotEmpty) '비교한 기준: ${f.reason}.',
        if (f.basis.isNotEmpty) '근거는 ${f.basis.map((b) => b.label).join(', ')}이에요.',
      ].join(' ');
}

/// 결과 카드 제목 옆에 붙는 작은 "새로" / "바뀜" 표시
class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.change});

  final _Change change;

  @override
  Widget build(BuildContext context) {
    final label = change == _Change.added ? '새로' : '바뀜';
    return Semantics(
      label: change == _Change.added ? '새로 생긴 항목' : '결과가 바뀐 항목',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// 문서만으로 알 수 없는 것을 묻는 카드. 답마다 큰 버튼 하나, 고른 답은 꽉 찬 색과 체크 표시
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.chosen, required this.onChoose});

  final Question question;

  /// 이미 고른 답 코드. 아직 안 골랐으면 null
  final String? chosen;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final options = question.options.entries.toList();
    final buttons = [
      for (final option in options)
        _OptionButton(
          label: option.value,
          selected: option.key == chosen,
          onPressed: () => onChoose(option.key),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.help_outline, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(question.text, style: text.bodyLarge)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 답이 셋 이하면 한 줄에 나란히, 많으면 위아래로 쌓는다
          if (buttons.length <= 3)
            Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: buttons[i]),
                ],
              ],
            )
          else
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              buttons[i],
            ],
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 8);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (selected) ...[const Icon(Icons.check), const SizedBox(width: 6)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(padding: padding),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(padding: padding),
              child: child,
            ),
    );
  }
}

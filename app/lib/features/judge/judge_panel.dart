import 'package:flutter/material.dart';

import '../../models/judgement.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../read/read_panel.dart' show ListenButton;

/// 판단("검토하세요!"): 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다.
/// 문서만으로 알 수 없는 것(예: 사업장 인원)은 먼저 질문으로 묻고, 답을 고르면 그 답으로 다시 판단한다.
/// 답을 고른 뒤에는 "무엇이 왜 달라졌는지"를 전후 개수와 함께 한 카드로 또렷이 보여주고 읽어준다.
/// 판정은 백엔드 규칙 엔진(backend/app/services/judge)이 한다. 이 화면은 결과를 보여주고 읽어주기만 한다.
class JudgePanel extends StatefulWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<JudgePanel> createState() => _JudgePanelState();
}

class _JudgePanelState extends State<JudgePanel> {
  /// 마지막으로 답한 질문과 그 전후 결과 비교. 아직 답하지 않았으면 null
  _JudgeDiff? _diff;

  /// "답 바꾸기"를 눌러 다시 고르는 중인 질문 id
  String? _editingQuestionId;

  /// 답할 때마다 1씩 올라간다. 결과 카드의 Key로 써서 답 하나당 liveRegion 알림이 한 번만 나가게 한다
  int _answerSeq = 0;

  @override
  void initState() {
    super.initState();
    // 창이 열리면 바로 판단하고, 물어볼 것이 있으면 질문부터, 그 다음 요약을 들려준다
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final judgement = await widget.state.judge();
      if (!mounted) return;
      if (judgement == null) {
        Speech.announce(context, widget.state.judgeError ?? '');
        return;
      }
      final pending = _pendingQuestion(judgement);
      Speech.announce(
        context,
        pending == null ? judgement.speech : '${pending.text} 아래 결과는 답에 따라 달라져요. 요약: ${judgement.speech}',
      );
    });
  }

  /// 아직 답하지 않았거나 다시 고르는 중인 질문. 없으면 null
  Question? _pendingQuestion(Judgement judgement) {
    for (final q in judgement.questions) {
      if (q.id == _editingQuestionId || widget.state.answers[q.id] == null) return q;
    }
    return null;
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
      final pending = _pendingQuestion(judgement);
      final diff = _diff;

      final findings = <Widget>[
        // 사라진 항목은 개수만이 아니라 이름을 줄 그어 보여준다
        if (pending == null && diff != null)
          for (final gone in diff.removed) _RemovedRow(finding: gone),
        for (final finding in _ordered(judgement.findings))
          _FindingCard(finding: finding, change: pending == null ? diff?.changeOf(finding) : null),
        if (judgement.findings.isEmpty) Text('특별히 확인이 필요한 항목을 찾지 못했어요.', style: text.bodyLarge),
      ];

      body = [
        // 1) 물어볼 것이 있으면 질문이 가장 먼저, 가장 크게
        if (pending != null)
          _QuestionCard(
            question: pending,
            chosen: state.answers[pending.id],
            onChoose: (code) => _answer(pending, code),
          )
        // 2) 답했으면 "무엇이 달라졌는지" 결과 카드
        else if (diff != null)
          _AnswerResultCard(
            key: ValueKey('answer-result-$_answerSeq'),
            diff: diff,
            onChange: () => setState(() => _editingQuestionId = diff.question.id),
          ),
        Text('확인이 필요한 곳 $caution개 · 빠진 항목 $missing개', style: text.titleMedium),
        const SizedBox(height: 8),
        if (pending != null) ...[
          // 답하기 전의 결과는 흐리게. 답에 따라 달라질 수 있다는 뜻
          Text('답하면 다시 검토해요', style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 6),
          Opacity(opacity: 0.55, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: findings)),
        ] else
          ...findings,
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

  /// 고른 답을 바로 읽어주고, 그 답으로 다시 판단한 뒤 무엇이 달라졌는지와 새 요약을 들려준다
  Future<void> _answer(Question question, String code) async {
    final label = question.options[code] ?? code;
    // 답을 바꾸려다 같은 답을 다시 고르면 다시 판단하지 않고 그대로 닫는다
    if (widget.state.answers[question.id] == code) {
      setState(() => _editingQuestionId = null);
      Speech.announce(context, '$label${_ro(label)} 그대로 두었어요.');
      return;
    }
    Speech.announce(context, '$label${_ro(label)} 답했어요. 다시 검토할게요.');
    final before = widget.state.judgement;
    final judgement = await widget.state.answer(question.id, code);
    if (!mounted) return;
    if (judgement == null) {
      Speech.announce(context, widget.state.judgeError ?? '');
      return;
    }
    final diff = _JudgeDiff.compare(before, judgement, question: question, label: label);
    setState(() {
      _diff = diff;
      _editingQuestionId = null;
      _answerSeq++;
    });
    // 달라진 점을 먼저, 요약을 그 다음에 한 번에 읽어서 중간에 끊기지 않게 한다
    Speech.announce(context, '${diff.speech} 요약: ${judgement.speech}');
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

/// 마지막 글자에 받침이 있는지 (한글이 아니면 false)
bool _hasBatchim(String word) {
  if (word.isEmpty) return false;
  final code = word.codeUnitAt(word.length - 1) - 0xAC00;
  return code >= 0 && code < 11172 && code % 28 != 0;
}

/// "~로/~으로" 조사. 받침 ㄹ은 "로"
String _ro(String word) {
  if (!_hasBatchim(word)) return '로';
  final code = word.codeUnitAt(word.length - 1) - 0xAC00;
  return code % 28 == 8 ? '로' : '으로';
}

/// "~라고/~이라고" 조사
String _rago(String word) => _hasBatchim(word) ? '이라고' : '라고';

/// 결과 항목 하나가 이전과 비교해 어떻게 달라졌는지
enum _Change { added, changed }

/// 답을 반영하기 전후의 판단 결과 비교. 항목은 ruleId(없으면 item)로 맞춘다
class _JudgeDiff {
  const _JudgeDiff({
    required this.question,
    required this.label,
    required this.added,
    required this.removed,
    required this.changed,
    required this.sentence,
    required this.countsText,
    required this.countsSpeech,
  });

  /// 답한 질문과 고른 답의 글자
  final Question question;
  final String label;

  final List<Finding> added;
  final List<Finding> removed;

  /// 같은 항목인데 수준(level)이 바뀐 것. 새 결과 기준
  final List<Finding> changed;

  /// 답이 무엇을 바꿨는지 쉬운 말로 한 문장(들)
  final String sentence;

  /// 화면용 전후 개수: "확인 필요 1개 → 0개 · 빠진 항목 2개 → 2개"
  final String countsText;

  /// 음성용 전후 개수: "확인 필요 1개에서 0개, 빠진 항목 2개에서 2개."
  final String countsSpeech;

  /// 음성으로 읽을 전체 문장
  String get speech => '$sentence $countsSpeech';

  static String _key(Finding f) => f.ruleId.isNotEmpty ? f.ruleId : f.item;

  /// 중요한 항목(확인 필요·빠짐)만 센다. 확인됨/알아두기가 오가는 것은 소리내어 알리지 않는다
  static bool _matters(Finding f) => f.level == 'caution' || f.level == 'missing';

  static String _names(List<Finding> list) =>
      list.map((f) => f.item).where((s) => s.isNotEmpty).map((s) => "'$s'").join(', ');

  static _JudgeDiff compare(Judgement? before, Judgement after, {required Question question, required String label}) {
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

    final cautionBefore = before?.counts['caution'] ?? 0, cautionAfter = after.counts['caution'] ?? 0;
    final missingBefore = before?.counts['missing'] ?? 0, missingAfter = after.counts['missing'] ?? 0;
    final countsText = '확인 필요 $cautionBefore개 → $cautionAfter개 · 빠진 항목 $missingBefore개 → $missingAfter개';
    final countsSpeech = '확인 필요 $cautionBefore개에서 $cautionAfter개, 빠진 항목 $missingBefore개에서 $missingAfter개.';

    final because = '$label${_rago(label)} 답해서,';
    final parts = <String>[
      if (removed.isNotEmpty) '$because ${_names(removed)} 항목은 이제 해당하지 않아요.',
      if (added.isNotEmpty) '$because ${_names(added)} 항목을 새로 확인해야 해요.',
      if (changed.isNotEmpty) '${_names(changed)} 항목의 결과가 바뀌었어요.',
    ];
    final sentence = parts.isEmpty
        ? '답을 반영했어요. 결과는 그대로예요: 확인 필요 $cautionAfter개, 빠진 항목 $missingAfter개.'
        : parts.join(' ');

    return _JudgeDiff(
      question: question,
      label: label,
      added: added,
      removed: removed,
      changed: changed,
      sentence: sentence,
      countsText: countsText,
      countsSpeech: countsSpeech,
    );
  }

  /// 결과가 나빠졌는지(새로 생기거나 더 심해짐). 카드 색을 고를 때 쓴다
  bool get worsened => added.isNotEmpty || changed.any(_matters);

  _Change? changeOf(Finding f) {
    final key = _key(f);
    if (added.any((a) => _key(a) == key)) return _Change.added;
    if (changed.any((c) => _key(c) == key)) return _Change.changed;
    return null;
  }
}

/// 답을 반영한 뒤 "무엇이 왜 달라졌는지"를 전후 개수와 함께 보여주는 카드.
/// 질문 카드가 있던 자리에 들어가서, 답이 결과를 바꿨다는 것이 한눈에 보이게 한다
class _AnswerResultCard extends StatelessWidget {
  const _AnswerResultCard({super.key, required this.diff, required this.onChange});

  final _JudgeDiff diff;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = diff.worsened ? AppColors.caution : AppColors.ok;
    final background = diff.worsened ? AppColors.cautionSoft : AppColors.okSoft;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(diff.worsened ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text('답을 반영했어요', style: text.titleMedium?.copyWith(color: color))),
              ],
            ),
            const SizedBox(height: 8),
            Text(diff.sentence, style: const TextStyle(color: AppColors.text, fontSize: 16.5, height: 1.4)),
            const SizedBox(height: 6),
            Text(diff.countsText, style: const TextStyle(color: AppColors.muted, fontSize: 14.5, height: 1.3)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text('답 바꾸기: ${diff.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 답을 반영해 사라진 항목. 개수만이 아니라 이름을 줄 그어 보여준다
class _RemovedRow extends StatelessWidget {
  const _RemovedRow({required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${finding.item}: 더 이상 해당하지 않아요',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.remove_circle_outline, color: AppColors.subtle, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: finding.item,
                        style: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.subtle),
                      ),
                      const TextSpan(text: ' — 더 이상 해당하지 않아요', style: TextStyle(color: AppColors.subtle)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ),
            ],
          ),
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
                // 첫 줄: 아이콘 + 제목 (+ 새로 생김/바뀜 표시)
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

/// 결과 카드 제목 옆에 붙는 작은 "새로 생김" / "바뀜" 표시
class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.change});

  final _Change change;

  @override
  Widget build(BuildContext context) {
    final added = change == _Change.added;
    return Semantics(
      label: added ? '답을 반영해 새로 생긴 항목' : '답을 반영해 결과가 바뀐 항목',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: added ? AppColors.primary : AppColors.missing,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          added ? '새로 생김' : '바뀜',
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// 문서만으로 알 수 없는 것을 묻는 카드. 화면 맨 위에 가장 크게 놓인다.
/// "먼저 알려주세요" → 질문 → 왜 묻는지 한 줄 → 큰 답 버튼. 고른 답은 꽉 찬 색과 체크 표시
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('먼저 알려주세요', style: text.titleMedium?.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(question.text, style: text.bodyLarge?.copyWith(fontSize: 19, height: 1.35)),
                const SizedBox(height: 4),
                Text('답에 따라 아래 결과가 달라져요.', style: text.bodyMedium?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
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

/// 질문의 답 버튼 하나. 손가락으로 찾기 쉽게 64 이상 높이, 글자 19
class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 12);
    const minimumSize = Size(0, 64);
    const textStyle = TextStyle(fontSize: 19, fontWeight: FontWeight.w600);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (selected) ...[const Icon(Icons.check, size: 24), const SizedBox(width: 6)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(padding: padding, minimumSize: minimumSize, textStyle: textStyle),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: padding,
                minimumSize: minimumSize,
                textStyle: textStyle,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              child: child,
            ),
    );
  }
}

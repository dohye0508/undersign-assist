import 'package:flutter/material.dart';

import '../../models/judgement.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../read/read_panel.dart' show ListenButton;
import '../../widgets/tap_feedback.dart';

/// 판단("검토하세요!"). 화면은 위에서 아래로 딱 네 덩어리다.
///   1. 검토 결과 듣기 버튼
///   2. 한 줄 결론 (+ 물어볼 것이 있으면 질문과 답 버튼, 답한 뒤에는 "무엇이 달라졌는지" 한 줄)
///   3. 번호 붙은 결과 목록 (제목 · 설명 · 근거 듣기)
///   4. 마지막 안내 한 줄
/// 글자 크기 셋(titleMedium, bodyLarge, bodyMedium), 색 셋(글자색, 흐린색, 상태색 하나)만 쓴다.
/// 판정은 백엔드 규칙 엔진(backend/app/services/judge)이 한다. 이 화면은 결과를 보여주고 읽어주기만 한다.
class JudgePanel extends StatefulWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<JudgePanel> createState() => _JudgePanelState();
}

class _JudgePanelState extends State<JudgePanel> {
  /// 마지막으로 답하기 직전의 결과. 새 결과와 견주어 "새로/바뀜"을 붙인다. 아직 답하지 않았으면 null
  Judgement? _before;

  /// 마지막으로 답한 질문과 고른 답의 글자
  Question? _answered;
  String _answeredLabel = '';

  /// 답한 줄을 눌러 답을 다시 고르는 중인지
  bool _editing = false;

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
      final pending = _unanswered(judgement);
      Speech.announce(
        context,
        pending == null ? judgement.speech : '${pending.text} 답에 따라 결과가 달라져요. 요약: ${judgement.speech}',
      );
    });
  }

  /// 아직 답하지 않은 첫 질문. 없으면 null
  Question? _unanswered(Judgement judgement) {
    for (final q in judgement.questions) {
      if (widget.state.answers[q.id] == null) return q;
    }
    return null;
  }

  static int _caution(Judgement? j) => j?.counts['caution'] ?? 0;
  static int _missing(Judgement? j) => j?.counts['missing'] ?? 0;

  /// 2번 덩어리의 한 줄 결론
  static String _conclusion(Judgement j) {
    final c = _caution(j), m = _missing(j);
    return c + m == 0 ? '특별히 확인할 것이 없어요.' : '확인할 곳 $c개, 빠진 것 $m개예요.';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final judgement = state.judgement;
    final text = Theme.of(context).textTheme;

    if (state.judging || (judgement == null && state.judgeError == null)) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [LinearProgressIndicator(), SizedBox(height: 8), Text('규칙과 법 조항으로 검토하고 있어요…')],
      );
    }
    if (judgement == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(state.judgeError!, style: text.bodyLarge),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: TapFeedback.wrap(state.judge), child: const Text('다시 검토하기')),
        ],
      );
    }

    final status = _caution(judgement) + _missing(judgement) > 0 ? AppColors.caution : AppColors.ok;
    final pending = _unanswered(judgement);
    // 답하지 않은 질문이 먼저. 다 답했고 답한 줄을 눌렀으면 그 질문을 다시 보여준다
    final question = pending ?? (_editing ? _answered : null);
    final findings = _ordered(judgement.findings);
    final disclaimer = judgement.disclaimer.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 듣기 버튼
        ListenButton(
          label: '검토 결과 듣기',
          icon: Icons.volume_up_outlined,
          primary: true,
          onPressed: () => Speech.announce(context, judgement.speech),
        ),
        const SizedBox(height: 16),

        // 2. 한 줄 결론 (+ 질문 또는 답한 줄)
        Text(_conclusion(judgement), style: text.titleMedium?.copyWith(color: status)),
        if (question != null) ...[
          const SizedBox(height: 12),
          Text(question.text, style: text.bodyLarge),
          for (final option in question.options.entries) ...[
            const SizedBox(height: 8),
            _optionButton(question, option.key, option.value),
          ],
        ] else if (_answered != null) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: TapFeedback.wrap(() => setState(() => _editing = true)),
            child: Semantics(
              button: true,
              hint: '누르면 답을 다시 고를 수 있어요',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_answeredLine(judgement), style: text.bodyLarge?.copyWith(color: AppColors.muted)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // 3. 번호 붙은 결과 목록
        for (var i = 0; i < findings.length; i++) ...[
          if (i > 0) const Divider(height: 16, thickness: 1, color: AppColors.line),
          _findingRow(context, i + 1, findings[i], status),
        ],

        // 4. 마지막 안내
        if (disclaimer.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(disclaimer, style: text.bodyMedium?.copyWith(color: AppColors.muted)),
        ],
      ],
    );
  }

  /// 질문의 답 버튼 하나. 이미 고른 답은 꽉 찬 색
  Widget _optionButton(Question question, String code, String label) {
    final selected = widget.state.answers[question.id] == code;
    final onPressed = TapFeedback.wrap(() => _answer(question, code));
    const size = Size.fromHeight(64);
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(minimumSize: size), child: Text(label))
          : OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(minimumSize: size), child: Text(label)),
    );
  }

  /// "{답}으로 답했어요 → 확인할 곳 1개 → 0개, 빠진 것 2→2."
  String _answeredLine(Judgement after) {
    final label = _answeredLabel;
    return '$label${_ro(label)} 답했어요 → 확인할 곳 ${_caution(_before)}개 → ${_caution(after)}개, '
        '빠진 것 ${_missing(_before)}→${_missing(after)}.';
  }

  /// 결과 한 항목: "n. 항목 — 상태" / 설명 한 줄 / 근거 듣기
  Widget _findingRow(BuildContext context, int n, Finding finding, Color status) {
    final text = Theme.of(context).textTheme;
    final statusWord = switch (finding.level) { 'caution' => '확인 필요', 'missing' => '빠짐', _ => '알아두기' };
    final prefix = switch (_changeOf(finding)) { _Change.added => '새로: ', _Change.changed => '바뀜: ', null => '' };
    final sentence = finding.speech.isNotEmpty ? finding.speech : finding.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: text.titleMedium?.copyWith(color: AppColors.text),
                  children: [
                    TextSpan(text: '$n. $prefix${finding.item} — '),
                    TextSpan(text: statusWord, style: TextStyle(color: status)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sentence,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: AppColors.text),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: TapFeedback.wrap(() => Speech.announce(context, _basisSpeech(finding))),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('근거 듣기'),
        ),
      ],
    );
  }

  /// 결과 문장 뒤에 법 조항 이름을 붙여 읽는다. 법 이름은 화면에 쓰지 않고 소리로만 준다
  static String _basisSpeech(Finding f) {
    final sentence = f.speech.isNotEmpty ? f.speech : f.reason;
    if (f.basis.isEmpty) return sentence;
    return '$sentence 근거는 ${f.basis.map((b) => b.label).join(', ')}이에요.';
  }

  /// 고른 답을 바로 읽어주고, 그 답으로 다시 판단한 뒤 한 줄 결론과 새 요약을 한 번에 들려준다
  Future<void> _answer(Question question, String code) async {
    final label = question.options[code] ?? code;
    // 답을 바꾸려다 같은 답을 다시 고르면 다시 판단하지 않고 그대로 닫는다
    if (widget.state.answers[question.id] == code) {
      setState(() => _editing = false);
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
    setState(() {
      _before = before;
      _answered = question;
      _answeredLabel = label;
      _editing = false;
    });
    Speech.announce(context, '${_conclusion(judgement)} 요약: ${judgement.speech}');
  }

  static String _key(Finding f) => f.ruleId.isNotEmpty ? f.ruleId : f.item;

  /// 마지막 답 전과 견주어 이 항목이 새로 생겼는지, 수준이 바뀌었는지
  _Change? _changeOf(Finding f) {
    final before = _before;
    if (before == null) return null;
    final key = _key(f);
    for (final old in before.findings) {
      if (_key(old) != key) continue;
      return old.level != f.level ? _Change.changed : null;
    }
    return _Change.added;
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

/// 결과 항목이 마지막 답 전과 비교해 어떻게 달라졌는지
enum _Change { added, changed }

/// "~로/~으로" 조사. 받침 ㄹ은 "로", 한글이 아니면 "로"
String _ro(String word) {
  if (word.isEmpty) return '로';
  final code = word.codeUnitAt(word.length - 1) - 0xAC00;
  if (code < 0 || code >= 11172) return '로';
  final tail = code % 28;
  return tail == 0 || tail == 8 ? '로' : '으로';
}

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
          icon: Icons.volume_up_rounded,
          onPressed: () => Speech.announce(context, judgement.speech),
        ),

        // 2. 한 줄 결론 (+ 질문 또는 답한 줄)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
          child: Text.rich(_conclusionSpan(judgement), style: _verdictStyle),
        ),
        if (question != null)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.grey50, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(question.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.5)),
                const SizedBox(height: 2),
                Text('답하면 결과가 바로 바뀌어요', style: text.bodySmall),
                const SizedBox(height: 12),
                _optionGrid(question),
              ],
            ),
          )
        else if (_answered != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Material(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: InkWell(
                onTap: TapFeedback.wrap(() => setState(() => _editing = true)),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Semantics(
                  button: true,
                  hint: '누르면 답을 다시 고를 수 있어요',
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_answeredLine(judgement), style: text.bodyMedium),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),

        // 3. 번호 붙은 결과 목록
        for (var i = 0; i < findings.length; i++)
          _findingRow(context, i + 1, findings[i], last: i == findings.length - 1),

        // 4. 마지막 안내
        if (disclaimer.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(disclaimer, style: text.bodySmall),
        ],
      ],
    );
  }

  static const _verdictStyle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.4);

  /// "확인할 곳 1개,\n빠진 것 2개예요." 앞부분은 상태 색
  static TextSpan _conclusionSpan(Judgement j) {
    final c = _caution(j), m = _missing(j);
    if (c + m == 0) return const TextSpan(text: '특별히 확인할 것이 없어요.');
    if (c == 0) {
      return TextSpan(children: [
        TextSpan(text: '빠진 것 $m개', style: const TextStyle(color: AppColors.missing)),
        const TextSpan(text: '가 있어요.'),
      ]);
    }
    return TextSpan(children: [
      TextSpan(text: '확인할 곳 $c개', style: const TextStyle(color: AppColors.caution)),
      TextSpan(text: m == 0 ? '가 있어요.' : ',\n빠진 것 $m개예요.'),
    ]);
  }

  /// 답 버튼을 두 개씩 한 줄에
  Widget _optionGrid(Question question) {
    final options = question.options.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _optionButton(question, options[i].key, options[i].value)),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < options.length
                    ? _optionButton(question, options[i + 1].key, options[i + 1].value)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 질문의 답 버튼 하나. 이미 고른 답은 꽉 찬 색, 나머지는 흰 바탕에 옅은 테두리
  Widget _optionButton(Question question, String code, String label) {
    final selected = widget.state.answers[question.id] == code;
    final onPressed = TapFeedback.wrap(() => _answer(question, code));
    const textStyle = TextStyle(fontFamily: AppFonts.body, fontSize: 18, fontWeight: FontWeight.w700);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
    final child = FittedBox(fit: BoxFit.scaleDown, child: Text(label, textAlign: TextAlign.center));
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), shape: shape, textStyle: textStyle),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                shape: shape,
                textStyle: textStyle,
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.grey200, width: 1.5),
              ),
              child: child,
            ),
    );
  }

  /// "{답}으로 답했어요 → 확인할 곳 1개 → 0개, 빠진 것 2→2."
  String _answeredLine(Judgement after) {
    final label = _answeredLabel;
    return '$label${_ro(label)} 답했어요 → 확인할 곳 ${_caution(_before)}개 → ${_caution(after)}개, '
        '빠진 것 ${_missing(_before)}→${_missing(after)}.';
  }

  /// 결과 한 항목: 번호와 제목 / 상태 꼬리표 / 설명 / 근거 듣기
  Widget _findingRow(BuildContext context, int n, Finding finding, {required bool last}) {
    final (statusWord, fg, bg) = switch (finding.level) {
      'caution' => ('확인 필요', AppColors.caution, AppColors.cautionSoft),
      'missing' => ('빠짐', AppColors.missing, AppColors.missingSoft),
      _ => ('알아두기', AppColors.muted, AppColors.grey100),
    };
    final prefix = switch (_changeOf(finding)) { _Change.added => '새로: ', _Change.changed => '바뀜: ', null => '' };
    final sentence = finding.speech.isNotEmpty ? finding.speech : finding.reason;
    const indent = 26.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.grey100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: indent,
                      child: Text(
                        '$n',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.muted, height: 1.4),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '$prefix${finding.item}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: indent, top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                    child: Text(statusWord, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: indent, top: 6),
                  child: Text(
                    sentence,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: indent - 8),
            child: TextButton.icon(
              onPressed: TapFeedback.wrap(() => Speech.announce(context, _basisSpeech(finding))),
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('근거 듣기'),
            ),
          ),
        ],
      ),
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

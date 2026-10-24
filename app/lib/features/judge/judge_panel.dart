import 'package:flutter/material.dart';

import '../../models/judgement.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../read/read_panel.dart' show ListenButton;
import '../../widgets/tap_feedback.dart';

/// 판단("검토하세요!").
///
/// 물어볼 것이 있으면 **결과보다 질문을 먼저** 한 화면에 크게 묻는다 (사용자 선택 Q2).
/// 무엇을 왜 묻는지("직원 수에 따라 근로시간 한도 초과, 연장·야간·휴일 가산수당 배제 검사가 달라져요")를 함께 말하고,
/// 답하거나 "모름"을 고르면 그때 결과가 나온다. 순서가 하나라 화면을 보지 않아도 헷갈리지 않는다.
///
/// 결과 화면: 검토 결과 듣기 → 한 줄 결론 → 답한 내용 한 줄(답 바꾸기) → 결과 목록 → 안내 한 줄.
/// 결과 목록은 칸마다 화면 끝까지 닿는 아주 옅은 색 띠(확인 필요 = 빨강, 빠짐 = 노랑, 알아두기 = 색 없음),
/// 상태는 제목 오른쪽 글자로 (사용자 선택 R1). 칸 사이는 흰 틈으로 나눈다.
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

  /// "답 바꾸기"를 눌러 질문 화면을 다시 보는 중인지
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    // 창이 열리면 바로 판단한다. 물어볼 것이 있으면 질문만 읽고, 결과는 답한 뒤에 읽는다
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final judgement = await widget.state.judge();
      if (!mounted) return;
      if (judgement == null) {
        Speech.announce(context, widget.state.judgeError ?? '');
        return;
      }
      final pending = _unanswered(judgement);
      Speech.announce(context, pending == null ? judgement.speech : _questionSpeech(pending));
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

  /// 한 줄 결론 (음성용)
  static String _conclusion(Judgement j) {
    final c = _caution(j), m = _missing(j);
    return c + m == 0 ? '특별히 확인할 것이 없어요.' : '확인할 곳 $c개, 빠진 것 $m개예요.';
  }

  /// "일하는 곳의 직원이 5명 이상인가요? 이에 따라 …"에서 물음 부분만
  static String _ask(Question q) {
    final i = q.text.indexOf('?');
    return i < 0 ? q.text : q.text.substring(0, i + 1);
  }

  /// 왜 묻는지: 답에 따라 달라지는 검사 이름. 이름이 없으면 질문 뒤 설명 문장
  static String _why(Question q) {
    if (q.affectsTitles.isNotEmpty) {
      return '답에 따라 ${q.affectsTitles.join(', ')} 검사가 달라져요. 모르면 모름을 골라도 돼요.';
    }
    final i = q.text.indexOf('?');
    final rest = i < 0 ? '' : q.text.substring(i + 1).trim();
    return rest.isEmpty ? '답에 따라 검토 결과가 달라져요.' : rest;
  }

  static String _questionSpeech(Question q) =>
      '검토 전에 한 가지 물어볼게요. ${_ask(q)} ${_why(q)} ${q.options.values.join(', ')} 중에서 고르세요.';

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

    // 답하지 않은 질문이 먼저. "답 바꾸기"를 눌렀으면 그 질문을 다시 보여준다
    final question = _unanswered(judgement) ?? (_editing ? _answered : null);
    if (question != null) return _questionFirst(question);

    final findings = _ordered(judgement.findings);
    final disclaimer = judgement.disclaimer.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenButton(
          label: '검토 결과 듣기',
          icon: Icons.volume_up_rounded,
          onPressed: () => Speech.announce(context, judgement.speech),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
          child: Text.rich(_conclusionSpan(judgement), style: _verdictStyle),
        ),
        if (_answered case final answered?) _answeredRow(answered),
        const SizedBox(height: 16),
        for (var i = 0; i < findings.length; i++) ...[
          if (i > 0) const SizedBox(height: 4), // 칸 사이 흰 틈
          _FullBleed(child: _findingRow(context, i + 1, findings[i])),
        ],
        if (disclaimer.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(disclaimer, style: text.bodySmall),
        ],
      ],
    );
  }

  // --- 질문 먼저 (Q2) ---------------------------------------------------------

  Widget _questionFirst(Question question) {
    final chosen = widget.state.answers[question.id];
    final options = question.options.entries.toList();
    // "모름"은 맨 아래 약한 버튼으로. 나머지는 위에서부터 큰 버튼
    final unknown = options.where((e) => e.key == 'unknown').toList();
    final main = options.where((e) => e.key != 'unknown').toList();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '검토 전에 한 가지',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent),
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(
              _ask(question),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _why(question),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textStrong, height: 1.6),
          ),
          const SizedBox(height: 18),
          for (final o in main) ...[
            _optionButton(question, o.key, o.value, selected: chosen == o.key),
            const SizedBox(height: 10),
          ],
          for (final o in unknown)
            _optionButton(question, o.key, '${o.value} (건너뛰기)', selected: chosen == o.key, weak: true),
        ],
      ),
    );
  }

  Widget _optionButton(Question question, String code, String label, {required bool selected, bool weak = false}) {
    return Semantics(
      selected: selected,
      child: FilledButton(
        onPressed: TapFeedback.wrap(() => _answer(question, code)),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(68),
          backgroundColor: weak ? AppColors.grey100 : AppColors.primary,
          foregroundColor: weak ? AppColors.textStrong : AppColors.onPrimary,
          side: selected ? const BorderSide(color: AppColors.accent, width: 3) : null,
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 19, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  /// 결과 위 한 줄: "'5명 이상'으로 답하고 검토했어요.  답 바꾸기"
  Widget _answeredRow(Question question) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(color: AppColors.grey50, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "'$_answeredLabel'${_ro(_answeredLabel)} 답하고 검토했어요.",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.5),
            ),
          ),
          TextButton(
            onPressed: TapFeedback.wrap(() {
              setState(() => _editing = true);
              Speech.announce(context, _questionSpeech(question));
            }),
            child: const Text('답 바꾸기'),
          ),
        ],
      ),
    );
  }

  // --- 결과 (R1) --------------------------------------------------------------

  static const _verdictStyle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.4);

  /// "확인할 곳 1개,\n빠진 것 2개예요." 각 부분은 그 상태 색
  static TextSpan _conclusionSpan(Judgement j) {
    final c = _caution(j), m = _missing(j);
    if (c + m == 0) return const TextSpan(text: '특별히 확인할 것이 없어요.');
    const red = TextStyle(color: AppColors.caution);
    const yellow = TextStyle(color: AppColors.missing);
    if (c == 0) {
      return TextSpan(children: [TextSpan(text: '빠진 것 $m개', style: yellow), const TextSpan(text: '가 있어요.')]);
    }
    return TextSpan(children: [
      TextSpan(text: '확인할 곳 $c개', style: red),
      if (m == 0) const TextSpan(text: '가 있어요.') else ...[
        const TextSpan(text: ',\n'),
        TextSpan(text: '빠진 것 $m개', style: yellow),
        const TextSpan(text: '예요.'),
      ],
    ]);
  }

  /// 결과 한 칸: 번호 · 제목 · 상태(오른쪽 글자) / 설명 / 근거 / 근거 듣기. 칸 전체를 상태 색으로 아주 옅게 칠한다
  Widget _findingRow(BuildContext context, int n, Finding finding) {
    final (statusWord, fg, bg) = switch (finding.level) {
      'caution' => ('확인 필요', AppColors.caution, AppColors.cautionSoft),
      'missing' => ('빠짐', AppColors.missing, AppColors.missingSoft),
      _ => ('알아두기', AppColors.muted, AppColors.surface),
    };
    final prefix = switch (_changeOf(finding)) { _Change.added => '새로: ', _Change.changed => '바뀜: ', null => '' };
    final sentence = finding.speech.isNotEmpty ? finding.speech : finding.reason;
    const indent = 26.0;
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(SectionBleed.size + 2, 16, SectionBleed.size + 2, 6),
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
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(statusWord, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
                    ),
                  ],
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
                // 근거 법 조항 ("근로기준법 제17조"). 소리로도 "근거 듣기"에서 읽는다
                if (finding.basis.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: indent, top: 6),
                    child: Text(
                      '근거  ${finding.basis.map((b) => b.label).join(', ')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted, height: 1.5),
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

  /// 결과 문장 뒤에 법 조항 이름을 붙여 읽는다
  static String _basisSpeech(Finding f) {
    final sentence = f.speech.isNotEmpty ? f.speech : f.reason;
    if (f.basis.isEmpty) return sentence;
    return '$sentence 근거는 ${f.basis.map((b) => b.label).join(', ')}이에요.';
  }

  /// 고른 답을 바로 읽어주고, 그 답으로 다시 판단한 뒤 한 줄 결론과 새 요약을 한 번에 들려준다
  Future<void> _answer(Question question, String code) async {
    final label = question.options[code] ?? code;
    // 답을 바꾸려다 같은 답을 다시 고르면 다시 판단하지 않고 그대로 닫는다
    if (widget.state.answers[question.id] == code && _answered != null) {
      setState(() => _editing = false);
      Speech.announce(context, '$label${_ro(label)} 그대로 두었어요. ${_conclusion(widget.state.judgement!)}');
      return;
    }
    Speech.announce(context, '$label${_ro(label)} 답했어요. 검토할게요.');
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

/// 분석 화면 본문의 좌우 여백. 결과 칸 색 띠는 이만큼 바깥으로 늘려 화면 끝까지 닿게 한다
class SectionBleed {
  static const size = 16.0;
}

/// 자식을 좌우로 [SectionBleed.size]씩 넓혀 화면 끝까지 닿게 그린다 (높이는 자식 그대로)
class _FullBleed extends StatelessWidget {
  const _FullBleed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 가로만 제약을 풀고 가운데 정렬해 좌우로 같은 만큼 넘친다. 넘친 띠 가장자리에는 버튼이 없어 눌림 영역 문제는 없다
    return LayoutBuilder(
      builder: (context, c) => UnconstrainedBox(
        constrainedAxis: Axis.vertical,
        clipBehavior: Clip.none,
        child: SizedBox(width: c.maxWidth + SectionBleed.size * 2, child: child),
      ),
    );
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

import 'package:flutter/material.dart';

import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import 'judgement.dart';

/// 판단: 읽기 결과를 법 기준(백엔드 규칙)과 비교해 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다.
/// AI가 아니라 규칙이 판단하고, 결과는 단정하지 않는다. 최종 판단은 사용자가 한다.
class JudgePanel extends StatefulWidget {
  const JudgePanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<JudgePanel> createState() => _JudgePanelState();
}

class _JudgePanelState extends State<JudgePanel> {
  Judgement? _result;
  RecognizedDocument? _forDocument; // 이 결과를 만든 읽기 결과
  final Map<String, String> _answers = {};
  bool _busy = false;
  String? _error;

  Future<void> _judge() async {
    final doc = widget.state.recognized;
    if (doc == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final json = await ApiClient.judge(doc, answers: _answers);
      final result = Judgement.fromJson(json);
      if (!mounted) return;
      setState(() {
        _result = result;
        _forDocument = doc;
        _busy = false;
      });
      await Speech.announce(context, result.speech);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '판단하지 못했어요. 서버가 켜져 있는지 확인하고 다시 눌러 주세요.';
      });
      await Speech.announce(context, _error!);
    }
  }

  Future<void> _answer(Question q, String value) async {
    _answers[q.id] = value;
    await _judge();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.state.recognized;
    // 새 사진을 읽으면 이전 판단은 지운다
    if (_result != null && !identical(_forDocument, doc)) {
      _result = null;
      _answers.clear();
    }
    final text = Theme.of(context).textTheme;
    final result = _result;

    return PanelSection(
      title: '빠진 것 확인',
      description: '빠진 항목과 확인이 필요한 내용을 법 기준과 비교해 근거와 함께 알려드려요. 결정은 직접 하세요.',
      children: [
        Semantics(
          button: true,
          label: '판단 듣기. 읽은 문서를 법 기준과 비교해서 결과를 음성으로 들려드려요',
          child: FilledButton(
            onPressed: doc == null || _busy ? null : _judge,
            child: Text(_busy ? '비교하는 중…' : (result == null ? '판단 듣기' : '다시 판단 듣기')),
          ),
        ),
        if (doc == null) ...[
          const SizedBox(height: 12),
          Text('먼저 문서를 찍거나 불러와 주세요.', style: text.bodyMedium),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_error!, style: text.bodyMedium)),
        ],
        if (result != null) ...[
          const SizedBox(height: 16),
          ...result.questions.map((q) => _QuestionCard(question: q, onAnswer: (v) => _answer(q, v))),
          if (result.findings.isEmpty)
            Text('특별히 확인이 필요한 항목을 찾지 못했어요.', style: text.bodyLarge)
          else
            ...result.findings.map((f) => _FindingCard(finding: f)),
          const SizedBox(height: 8),
          Text(result.disclaimer, style: text.bodySmall),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.onAnswer});

  final Question question;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final options = question.options.isEmpty
        ? const {'yes': '예', 'no': '아니요', 'unknown': '모름'}
        : question.options;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(liveRegion: true, child: Text(question.text, style: Theme.of(context).textTheme.bodyLarge)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in options.entries)
                Semantics(
                  button: true,
                  label: '${question.text} 답: ${e.value}',
                  child: OutlinedButton(onPressed: () => onAnswer(e.key), child: Text(e.value)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Kind {
  const _Kind(this.label, this.icon, this.color, this.background);

  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  static const ok = _Kind('확인됨', Icons.check_circle_outline, AppColors.ok, AppColors.okSoft);
  static const missing = _Kind('빠짐', Icons.help_outline, AppColors.missing, AppColors.missingSoft);
  static const caution = _Kind('확인 필요', Icons.error_outline, AppColors.caution, AppColors.cautionSoft);
  static const info = _Kind('알아두기', Icons.info_outline, AppColors.primary, AppColors.primarySoft);

  static _Kind of(String level) => switch (level) {
        'ok' => ok,
        'missing' => missing,
        'caution' => caution,
        _ => info,
      };
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});

  final Finding finding;

  String _basisSpeech() {
    if (finding.basis.isEmpty) return '이 항목에 붙은 근거 조문이 없어요.';
    return finding.basis.map((b) => '${b.lawName} ${b.articleNo} ${b.title}. ${b.excerpt}').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final kind = _Kind.of(finding.level);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kind.background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(kind.icon, color: kind.color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('${kind.label} · ${finding.item}', style: TextStyle(color: kind.color, fontSize: 18)),
                ),
                const SizedBox(height: 4),
                Text(finding.speech, style: text.bodyMedium),
                if (finding.reason.isNotEmpty) Text('비교: ${finding.reason}', style: text.bodySmall),
                if (finding.evidence.isNotEmpty) Text('문서 원문: "${finding.evidence}"', style: text.bodySmall),
                for (final b in finding.basis)
                  Text('근거: ${b.lawName} ${b.articleNo}(${b.title})', style: text.bodySmall),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: '${finding.item} 근거 듣기',
                  child: OutlinedButton(
                    onPressed: () => Speech.announce(context, _basisSpeech()),
                    child: const Text('근거 듣기'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

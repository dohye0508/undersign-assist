import 'package:flutter/material.dart';

import '../../models/document_session.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../widgets/step_view.dart';

/// 판단: 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다.
class JudgeStep extends StatefulWidget {
  const JudgeStep({super.key, required this.session});

  final DocumentSession session;

  @override
  State<JudgeStep> createState() => _JudgeStepState();
}

class _JudgeStepState extends State<JudgeStep> {
  bool _busy = false;
  String? _result;

  Future<void> _judge() async {
    final document = widget.session.recognized;
    if (document == null) {
      setState(() => _result = '먼저 읽기에서 문서를 읽어 주세요.');
      Speech.announce(context, _result!);
      return;
    }
    setState(() => _busy = true);
    try {
      final judgement = await ApiClient.judge(document);
      // TODO: 주의 항목이 있으면 경고음 (하드웨어 진동 대신)
      _result = judgement['speech'] as String?;
    } catch (_) {
      _result = '판단하지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, _result ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return StepView(
      title: '판단',
      description: '빠진 항목과 확인이 필요한 내용을 근거와 함께 알려드려요. 결정은 직접 하세요.',
      actionLabel: '판단 듣기',
      onAction: _judge,
      busy: _busy,
      result: _result,
    );
  }
}

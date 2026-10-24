import 'package:flutter/material.dart';

import '../../models/document_session.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../widgets/step_view.dart';

/// 읽기: 문서 종류를 알아내고 핵심 항목을 음성으로 읽어준다.
/// 결과를 [DocumentSession]에 넣어 판단, 쓰기, 서명이 이어받게 한다.
class ReadStep extends StatefulWidget {
  const ReadStep({super.key, required this.session});

  final DocumentSession session;

  @override
  State<ReadStep> createState() => _ReadStepState();
}

class _ReadStepState extends State<ReadStep> {
  bool _busy = false;
  String? _result;

  Future<void> _read() async {
    setState(() => _busy = true);
    try {
      final document = await ApiClient.read(widget.session.photo);
      widget.session.recognized = document;
      _result = document.speech;
    } catch (_) {
      _result = '문서를 읽지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, _result!);
  }

  @override
  Widget build(BuildContext context) {
    return StepView(
      title: '읽기',
      description: '문서가 무엇인지 알아내고 중요한 내용을 읽어드려요.',
      actionLabel: '문서 읽기',
      onAction: _read,
      busy: _busy,
      result: _result,
    );
  }
}

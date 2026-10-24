import 'package:flutter/material.dart';

import '../../models/document_session.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../widgets/step_view.dart';

/// 서명: 서명란 위치를 안내하고, 서명하기 전에 동의 여부를 마지막으로 확인한다.
class SignStep extends StatefulWidget {
  const SignStep({super.key, required this.session});

  final DocumentSession session;

  @override
  State<SignStep> createState() => _SignStepState();
}

class _SignStepState extends State<SignStep> {
  bool _busy = false;
  String? _result;

  Future<void> _locate() async {
    setState(() => _busy = true);
    // TODO: 판단 결과에 주의 항목이 있으면 서명 전에 다시 알려주고 동의를 묻기
    try {
      final spot = await ApiClient.locateSignature(widget.session.photo);
      _result = spot['speech'] as String?;
    } catch (_) {
      _result = '서명란을 찾지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, _result ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return StepView(
      title: '서명',
      description: '서명란이 어디인지 알려드려요. 서명하기 전에 판단 결과를 한 번 더 들려드려요.',
      actionLabel: '서명란 찾기',
      onAction: _locate,
      busy: _busy,
      result: _result,
    );
  }
}

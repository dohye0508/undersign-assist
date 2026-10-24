import 'package:flutter/material.dart';

import '../../models/document_session.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../widgets/step_view.dart';

/// 쓰기: 써야 할 칸을 안내하고, 종이에 펜으로 쓴 글씨를 다시 찍어 무엇을 썼는지 읽어준다.
class WriteStep extends StatefulWidget {
  const WriteStep({super.key, required this.session});

  final DocumentSession session;

  @override
  State<WriteStep> createState() => _WriteStepState();
}

class _WriteStepState extends State<WriteStep> {
  bool _busy = false;
  String? _result;

  Future<void> _check() async {
    setState(() => _busy = true);
    // TODO: 읽기 결과에서 빈칸 목록을 받아 지금 쓸 칸을 고르게 하기
    // TODO: 쓴 뒤에 다시 찍은 사진을 받기 (지금은 처음 사진을 쓴다)
    const field = '성명';
    try {
      final check = await ApiClient.checkWriting(widget.session.photo, field);
      _result = check['speech'] as String?;
    } catch (_) {
      _result = '글씨를 확인하지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, _result ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return StepView(
      title: '쓰기',
      description: '써야 할 칸을 알려드려요. 종이에 펜으로 쓴 뒤 다시 찍으면 무엇을 썼는지 읽어드려요.',
      actionLabel: '쓴 글씨 확인',
      onAction: _check,
      busy: _busy,
      result: _result,
    );
  }
}

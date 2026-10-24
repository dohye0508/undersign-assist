import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../widgets/panel_section.dart';

/// 읽기: 사진을 받으면 자동으로 읽은 결과(문서 종류, 핵심 항목)를 보여주고 다시 들려준다.
class ReadPanel extends StatefulWidget {
  const ReadPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<ReadPanel> createState() => _ReadPanelState();
}

class _ReadPanelState extends State<ReadPanel> {
  bool _showFullText = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final document = state.recognized;

    final List<Widget> body;
    if (state.reading) {
      body = [const LinearProgressIndicator(), const SizedBox(height: 12), const Text('문서를 읽고 있어요…')];
    } else if (state.readError != null) {
      body = [
        Text(state.readError!),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: state.read, child: const Text('다시 읽기')),
      ];
    } else if (document == null) {
      body = [OutlinedButton(onPressed: state.read, child: const Text('문서 읽기'))];
    } else {
      body = [
        LabelValueRow(label: '문서 종류', value: document.docTypeLabel),
        for (final field in document.fields) LabelValueRow(label: field.label, value: field.value),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Speech.announce(context, document.speech),
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('요약 다시 듣기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Speech.announce(context, document.fullText),
          icon: const Icon(Icons.record_voice_over_outlined),
          label: const Text('전체 듣기'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _showFullText = !_showFullText),
          child: Text(_showFullText ? '인식한 글자 숨기기' : '인식한 글자 보기'),
        ),
        if (_showFullText) SelectableText(document.fullText),
      ];
    }

    return PanelSection(
      title: '문서 읽기',
      description: '어떤 문서인지와 중요한 항목을 읽어드려요.',
      children: body,
    );
  }
}

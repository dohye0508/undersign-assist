import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 읽기: 사진을 받으면 자동으로 읽은 결과(문서 종류, 핵심 항목)를 보여주고 다시 들려준다.
/// 모양은 디자인 시안의 "분석 결과" 화면을 따른다 (위에 숫자 칸 세 개, 아래 카드).
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
      body = [
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [LinearProgressIndicator(), SizedBox(height: 12), Text('문서를 읽고 있어요…')],
          ),
        ),
      ];
    } else if (state.readError != null) {
      body = [
        AppCard(child: Text(state.readError!)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: state.read, child: const Text('다시 읽기')),
      ];
    } else if (document == null) {
      body = [OutlinedButton(onPressed: state.read, child: const Text('문서 읽기'))];
    } else {
      body = [
        Row(
          children: [
            StatTile(value: document.docTypeLabel, label: '문서 종류'),
            const SizedBox(width: 8),
            StatTile(value: '${document.fields.length}', label: '찾은 항목'),
            const SizedBox(width: 8),
            StatTile(value: document.reader == 'ai' ? 'AI' : '규칙', label: '정리 방식'),
          ],
        ),
        const SizedBox(height: 12),
        if (document.fields.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(
              children: [
                for (final (i, field) in document.fields.indexed)
                  LabelValueRow(label: field.label, value: field.value, last: i == document.fields.length - 1),
              ],
            ),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => Speech.announce(context, document.speech),
          icon: const Icon(Icons.volume_up_rounded),
          label: const Text('요약 다시 듣기'),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => Speech.announce(context, document.fullText),
              icon: const Icon(Icons.record_voice_over_outlined, size: 18),
              label: const Text('원문 전체 듣기'),
            ),
            TextButton(
              onPressed: () => setState(() => _showFullText = !_showFullText),
              child: Text(_showFullText ? '인식한 글자 숨기기' : '인식한 글자 보기'),
            ),
          ],
        ),
        if (_showFullText)
          AppCard(child: SelectableText(document.fullText, style: const TextStyle(color: AppColors.muted))),
      ];
    }

    return PanelSection(
      title: '읽기',
      description: '어떤 문서인지와 중요한 항목을 읽어드려요.',
      children: body,
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';

/// 읽기: 사진을 받으면 자동으로 읽은 결과(문서 종류, 핵심 항목)를 보여주고 다시 들려준다.
class ReadPanel extends StatelessWidget {
  const ReadPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
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
      // 새 문서를 읽으면 펼침 상태를 처음(접힘)으로 돌린다
      body = [ReadSummary(key: ObjectKey(document), document: document)];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 듣기는 이 앱에서 가장 많이 쓰는 동작이다. 화면을 보지 않고도 찾도록 맨 위에 크게 둔다
        if (document != null && !state.reading) ...[
          ListenButton(
            label: '전체 듣기',
            icon: Icons.record_voice_over_outlined,
            primary: true,
            onPressed: () => Speech.announce(context, document.fullText),
          ),
          const SizedBox(height: 12),
          ListenButton(
            label: '요약 듣기',
            icon: Icons.volume_up_outlined,
            onPressed: () => Speech.announce(context, document.speech),
          ),
          const SizedBox(height: 24),
        ],
        PanelSection(
          title: WorkStep.read.label,
          description: '어떤 문서인지와 중요한 항목을 읽어드려요.',
          children: body,
        ),
      ],
    );
  }
}

/// 화면 맨 위에 두는 큰 듣기 버튼
class ListenButton extends StatelessWidget {
  const ListenButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// 가장 먼저 누를 버튼 (꽉 찬 색)
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const size = Size.fromHeight(88);
    const textStyle = TextStyle(fontFamily: AppFonts.body, fontSize: 26);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon, size: 36), const SizedBox(width: 14), Text(label)],
    );
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(minimumSize: size, textStyle: textStyle),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: size, textStyle: textStyle),
            child: child,
          );
  }
}

/// 읽은 결과를 한 줄로 알려주고, 항목 목록과 인식한 글자는 버튼을 눌렀을 때만 펼친다.
/// 처음부터 목록을 다 펼치면 화면이 길어져 확대해서 보는 사용자가 길을 잃는다.
class ReadSummary extends StatefulWidget {
  const ReadSummary({super.key, required this.document});

  final RecognizedDocument document;

  @override
  State<ReadSummary> createState() => _ReadSummaryState();
}

class _ReadSummaryState extends State<ReadSummary> {
  bool _showFields = false;
  bool _showFullText = false;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final text = Theme.of(context).textTheme;
    // 페이지 정보가 없는 예전 응답도 사진 한 장으로 본다
    final pageCount = document.pages.isEmpty ? 1 : document.pages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${document.docTypeLabel} · $pageCount페이지 · 항목 ${document.fields.length}개',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 10),
        _ToggleButton(
          open: _showFields,
          openLabel: '요약 접기',
          closedLabel: '요약 보기',
          onPressed: () => setState(() => _showFields = !_showFields),
        ),
        AnimatedSize(
          duration: _duration,
          alignment: Alignment.topCenter,
          child: _showFields
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabelValueRow(label: '문서 종류', value: document.docTypeLabel),
                    for (final field in document.fields) LabelValueRow(label: field.label, value: field.value),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 10),
        _ToggleButton(
          open: _showFullText,
          openLabel: '인식한 글자 숨기기',
          closedLabel: '인식한 글자 보기',
          onPressed: () => setState(() => _showFullText = !_showFullText),
        ),
        AnimatedSize(
          duration: _duration,
          alignment: Alignment.topCenter,
          child: _showFullText
              ? SelectableText(document.fullText, style: text.bodyLarge)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 펼치기/접기 버튼. 화살표 아이콘과 글자가 함께 바뀌고, 스크린리더에는 펼침 상태를 알린다.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.open,
    required this.openLabel,
    required this.closedLabel,
    required this.onPressed,
  });

  final bool open;
  final String openLabel;
  final String closedLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        expanded: open,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(open ? Icons.expand_less : Icons.expand_more),
          label: Text(open ? openLabel : closedLabel),
        ),
      ),
    );
  }
}

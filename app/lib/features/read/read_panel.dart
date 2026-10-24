import 'package:flutter/material.dart';

import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import '../fill/fill_targets.dart';
import '../../widgets/tap_feedback.dart';

/// 읽기: 사진을 받으면 자동으로 읽은 결과(문서 종류, 핵심 항목)를 보여주고 다시 들려준다.
///
/// 맨 위 큰 듣기 버튼 → 쉬운 말로 된 설명 한 문단 → 항목 표. 펼치기/접기는 두지 않는다.
/// 단계 이름은 상단 바가 이미 보여 주므로 제목을 다시 쓰지 않는다.
class ReadPanel extends StatelessWidget {
  const ReadPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final document = state.recognized;

    if (state.reading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [LinearProgressIndicator(), SizedBox(height: 8), Text('문서를 읽고 있어요…')],
      );
    }
    if (state.readError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(state.readError!),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: TapFeedback.wrap(state.read), child: const Text('다시 읽기')),
        ],
      );
    }
    if (document == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [OutlinedButton(onPressed: TapFeedback.wrap(state.read), child: const Text('문서 읽기'))],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 듣기는 이 앱에서 가장 많이 쓰는 동작이다. 화면을 보지 않고도 찾도록 맨 위에 크게 하나만 둔다.
        ListenButton(
          label: '요약 듣기',
          icon: Icons.volume_up_outlined,
          primary: true,
          onPressed: () => Speech.announce(context, document.speech),
        ),
        const SizedBox(height: 16),
        ReadSummary(document: document),
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
    const size = Size.fromHeight(72);
    const textStyle = TextStyle(fontFamily: AppFonts.body, fontSize: 22);
    const padding = EdgeInsets.symmetric(horizontal: 12);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 30),
        const SizedBox(width: 10),
        // 좁은 화면에서 나란히 놓여도 넘치지 않게 글자를 줄여 맞춘다
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label))),
      ],
    );
    return primary
        ? FilledButton(
            onPressed: TapFeedback.wrap(onPressed),
            style: FilledButton.styleFrom(minimumSize: size, padding: padding, textStyle: textStyle),
            child: child,
          )
        : OutlinedButton(
            onPressed: TapFeedback.wrap(onPressed),
            style: OutlinedButton.styleFrom(minimumSize: size, padding: padding, textStyle: textStyle),
            child: child,
          );
  }
}

/// 읽은 결과를 쉬운 말 한 문단으로 설명하고, 그 아래에 항목 표를 늘 펼쳐 보여 준다.
class ReadSummary extends StatelessWidget {
  const ReadSummary({super.key, required this.document});

  final RecognizedDocument document;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(describeDocument(document), style: text.bodyLarge),
        const SizedBox(height: 12),
        LabelValueRow(label: '문서 종류', value: document.docTypeLabel),
        for (final field in document.fields) LabelValueRow(label: field.label, value: field.value),
      ],
    );
  }
}

/// "사진 1장은 근로계약서예요. 중요한 항목 7개를 찾았고, 써야 할 칸은 3곳이에요."
///
/// 읽기 결과만으로 쓸 칸까지 세어 한 문단에 담는다. 쓸 칸이 없으면 "써야 할 칸은 찾지 못했어요."
String describeDocument(RecognizedDocument document) {
  // 페이지 정보가 없는 예전 응답도 사진 한 장으로 본다
  final pageCount = document.pages.isEmpty ? 1 : document.pages.length;
  final fillCount = findFillTargets(document).length;
  final kind = josa(document.docTypeLabel, '이에요', '예요');
  final fill = fillCount == 0 ? '써야 할 칸은 찾지 못했어요.' : '써야 할 칸은 $fillCount곳이에요.';
  return '사진 $pageCount장은 $kind. 중요한 항목 ${document.fields.length}개를 찾았고, $fill';
}

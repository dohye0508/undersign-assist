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
    final text = Theme.of(context).textTheme;

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

    final pageCount = document.pages.isEmpty ? 1 : document.pages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 문서 이름을 큰 제목으로. 위 작은 줄에 단계와 페이지 수
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 22),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '문서 읽기 · $pageCount페이지',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
                ),
                const SizedBox(height: 6),
                Semantics(header: true, child: Text(document.docTypeLabel, style: text.headlineMedium)),
              ],
            ),
          ),
        ),
        // 듣기는 이 앱에서 가장 많이 쓰는 동작이다. 화면을 보지 않고도 찾도록 맨 위에 크게 하나만 둔다.
        ListenButton(
          label: '요약 듣기',
          icon: Icons.volume_up_rounded,
          onPressed: () => Speech.announce(context, document.speech),
        ),
        ReadSummary(document: document),
      ],
    );
  }
}

/// 화면 맨 위에 두는 큰 듣기 버튼. 옅은 파랑 바탕에 파란 글씨 (토스의 약한 강조 버튼)
class ListenButton extends StatelessWidget {
  const ListenButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: TapFeedback.wrap(onPressed),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(68),
        backgroundColor: AppColors.primarySoft,
        foregroundColor: AppColors.primarySoftInk,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 19, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 10),
          // 좁은 화면에서도 넘치지 않게 글자를 줄여 맞춘다
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label))),
        ],
      ),
    );
  }
}

/// 읽은 결과를 쉬운 말 한 문단으로 설명하고, 그 아래에 항목 표를 늘 펼쳐 보여 준다.
class ReadSummary extends StatelessWidget {
  const ReadSummary({super.key, required this.document});

  final RecognizedDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
          child: Text.rich(
            highlightCounts(describeDocument(document)),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.6),
          ),
        ),
        if (document.fields.isNotEmpty) ...[
          const SectionHeading('중요한 항목'),
          for (final field in document.fields) LabelValueRow(label: field.label, value: field.value),
        ],
      ],
    );
  }
}

/// 문장 속 "5개", "7곳" 같은 수를 굵은 파랑으로
TextSpan highlightCounts(String sentence) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in RegExp(r'\d+(개|곳)').allMatches(sentence)) {
    spans.add(TextSpan(text: sentence.substring(last, m.start)));
    spans.add(TextSpan(
      text: m.group(0),
      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
    ));
    last = m.end;
  }
  spans.add(TextSpan(text: sentence.substring(last)));
  return TextSpan(children: spans);
}

/// "3페이지짜리 개인정보 동의서예요. 중요한 항목 7개를 찾았고, 써야 할 칸은 5곳이에요(1·3페이지)."
///
/// 여러 장은 한 문서의 여러 페이지로만 말한다. 페이지별로 반복하면 길어지므로
/// 쓸 칸이 있는 페이지 번호만 괄호에 넣는다. 쓸 칸이 없으면 "써야 할 칸은 찾지 못했어요."
String describeDocument(RecognizedDocument document) {
  final pageCount = document.pages.isEmpty ? 1 : document.pages.length;
  final targets = findFillTargets(document);
  final doc = pageCount > 1 ? '$pageCount페이지짜리 ${document.docTypeLabel}' : document.docTypeLabel;
  final kind = josa(doc, '이에요', '예요');
  final String fill;
  if (targets.isEmpty) {
    fill = '써야 할 칸은 찾지 못했어요.';
  } else {
    final pages = ({for (final t in targets) t.page + 1}.toList()..sort()).join('·');
    fill = '써야 할 칸은 ${targets.length}곳이에요${pageCount > 1 ? '($pages페이지)' : ''}.';
  }
  return '$kind. 중요한 항목 ${document.fields.length}개를 찾았고, $fill';
}

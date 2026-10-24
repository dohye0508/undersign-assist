import 'package:flutter/material.dart';

import '../features/judge/judge_step.dart';
import '../features/read/read_step.dart';
import '../features/sign/sign_step.dart';
import '../features/write/write_step.dart';
import '../models/document_session.dart';
import '../theme/app_theme.dart';

/// 사진을 받은 뒤의 화면. 네 단계를 실제 사용 순서(읽기 → 판단 → 쓰기 → 서명)로 보여준다.
/// 판단을 거치지 않고 서명하게 만들지 않으려고 판단을 서명보다 앞에 둔다.
class DocumentScreen extends StatelessWidget {
  const DocumentScreen({super.key, required this.session});

  final DocumentSession session;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, Widget)>[
      ('읽기', ReadStep(session: session)),
      ('판단', JudgeStep(session: session)),
      ('쓰기', WriteStep(session: session)),
      ('서명', SignStep(session: session)),
    ];

    return DefaultTabController(
      length: steps.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('문서'),
          bottom: TabBar(tabs: [for (final (label, _) in steps) Tab(text: label, height: 64)]),
        ),
        body: Column(
          children: [
            // 시력이 조금 남은 사용자를 위해 받은 사진을 작게 보여준다
            Container(
              height: 160,
              margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                image: true,
                label: '받은 문서 사진',
                child: Image.memory(session.photo.bytes, fit: BoxFit.contain),
              ),
            ),
            Expanded(
              child: TabBarView(children: [for (final (_, view) in steps) view]),
            ),
          ],
        ),
      ),
    );
  }
}

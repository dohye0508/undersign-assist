import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/widgets/step_progress.dart';

Widget _wrap(double width, StepProgress child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  testWidgets('좁은 폭에 30칸이면 한 줄 막대 + "3 / 30"', (tester) async {
    await tester.pumpWidget(_wrap(
      320,
      const StepProgress(count: 30, filled: {0, 1}, current: 2, semanticLabel: '30개 중 3번째, 2개 입력했어요'),
    ));

    expect(StepProgress.fitsDots(30, 320), isFalse);
    expect(find.byKey(const Key('step-progress-bar')), findsOneWidget);
    expect(find.byKey(const Key('step-progress-dots')), findsNothing);
    expect(find.text('3 / 30'), findsOneWidget);
    // 줄바꿈 없이 한 줄 높이
    expect(tester.getSize(find.byType(StepProgress)).height, StepProgress.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 폭에 7칸이면 동그라미 7개', (tester) async {
    await tester.pumpWidget(_wrap(
      440,
      const StepProgress(count: 7, filled: {0, 1}, current: 2, semanticLabel: '채울 곳 7개 중 3번째, 2개 채움'),
    ));

    expect(find.byKey(const Key('step-progress-dots')), findsOneWidget);
    expect(find.byKey(const Key('step-progress-bar')), findsNothing);
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('step-dot-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('step-dot-7')), findsNothing);
    expect(tester.getSize(find.byType(StepProgress)).height, StepProgress.height);
  });

  testWidgets('스크린리더에는 한 문장만', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(
      320,
      const StepProgress(count: 14, filled: {0, 1}, current: 2, semanticLabel: '채울 곳 14개 중 3번째, 2개 채움'),
    ));
    expect(find.bySemanticsLabel('채울 곳 14개 중 3번째, 2개 채움'), findsOneWidget);
    expect(find.bySemanticsLabel('3 / 14'), findsNothing);
    handle.dispose();
  });
}

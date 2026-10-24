import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/widgets/app_logo.dart';
import 'package:undersign_assist/widgets/splash_gate.dart';

Widget _app() => const MaterialApp(home: SplashGate(child: Scaffold(body: Text('메인'))));

void main() {
  testWidgets('시작 화면은 3.5초 동안 보이다가 사라진다', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.byType(AppLogo), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3400));
    expect(find.byType(AppLogo), findsOneWidget, reason: '3.4초에는 아직 걷히는 중');

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AppLogo), findsNothing, reason: '3.6초에는 끝');
    expect(find.text('메인'), findsOneWidget);
  });

  testWidgets('걷히는 동안에도 메인 화면은 이미 그려져 있다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.text('메인'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
  });

  test('걷힘 진행도는 머무는 동안 0, 끝에서 1이고 줄어들지 않는다', () {
    // 머묾이 끝나기 전(나타남 0.6초 + 머묾 1.6초 = 2.2초)까지 0
    expect(SplashGate.wipeProgress(0), 0);
    expect(SplashGate.wipeProgress(0.5), 0);
    expect(SplashGate.wipeProgress(SplashGate.wipeStart), 0);
    expect(SplashGate.wipeProgress(1), 1);
    var last = 0.0;
    for (var i = 0; i <= 100; i++) {
      final v = SplashGate.wipeProgress(i / 100);
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
  });
}

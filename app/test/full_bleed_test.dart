import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/judge/full_bleed.dart';

void main() {
  testWidgets(
    'finding background reaches both page edges and keeps its content height',
    (tester) async {
      const page = Key('page'), row = Key('row'), next = Key('next');
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: page,
              width: 320,
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      FullBleed(
                        inset: 16,
                        child: SizedBox(key: row, height: 80),
                      ),
                      SizedBox(key: next, height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final pageRect = tester.getRect(find.byKey(page));
      final rowRect = tester.getRect(find.byKey(row));
      expect(rowRect.left, pageRect.left);
      expect(rowRect.right, pageRect.right);
      expect(rowRect.height, 80);
      expect(tester.getTopLeft(find.byKey(next)).dy, rowRect.bottom);
    },
  );

  testWidgets(
    'long finding content gives the scroll layout a finite natural height',
    (tester) async {
      const body = Key('body'), next = Key('next');
      final content = List.filled(100, '원문에서 확인할 항목입니다.').join(' ');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      FullBleed(inset: 16, child: Text(content, key: body)),
                      const SizedBox(key: next, height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final bodyRect = tester.getRect(find.byKey(body));
      expect(bodyRect.height.isFinite, isTrue);
      expect(bodyRect.height, greaterThan(100));
      expect(bodyRect.width, 240);
      expect(tester.getTopLeft(find.byKey(next)).dy, bodyRect.bottom);
    },
  );
}

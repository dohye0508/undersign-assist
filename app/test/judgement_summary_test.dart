import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/judge/judgement_summary.dart';
import 'package:undersign_assist/models/judgement.dart';
import 'fixtures/judgement_responses.dart';

void main() {
  test('unsupported backend response is not an all-clear conclusion', () {
    expect(
      judgementConclusion(Judgement.fromJson(incompleteJudgements['unknown']!)),
      '이 문서의 자동 검토를 완료하지 못했어요.',
    );
  });
  test(
    'unread receipt fields retain the requirement to check the original',
    () {
      expect(
        judgementConclusion(
          Judgement.fromJson(incompleteJudgements['receipt']!),
        ),
        '읽지 못한 항목이 있어요. 원문을 확인해 주세요.',
      );
    },
  );
  test('informational guidance is presented as guidance', () {
    expect(
      judgementConclusion(
        Judgement.fromJson({
          'findings': [
            {'rule_id': 'form_receipt_guide', 'level': 'info'},
          ],
          'counts': {'info': 1},
        }),
      ),
      '확인 안내가 있어요. 원문과 함께 살펴보세요.',
    );
  });
  test('actionable counts remain visible', () {
    expect(
      judgementConclusion(
        Judgement.fromJson({
          'counts': {'caution': 2, 'missing': 1},
        }),
      ),
      '확인할 곳 2개, 빠진 것 1개예요.',
    );
  });
  test('completed checks without findings retain the clear conclusion', () {
    expect(
      judgementConclusion(Judgement.fromJson({'findings': [], 'counts': {}})),
      '특별히 확인할 것이 없어요.',
    );
  });
}

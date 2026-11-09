import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/fill_kind.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/features/sign/signature_spots.dart';
import 'package:undersign_assist/models/recognized_document.dart';

RecognizedDocument doc(String kind, List<String> rows) => RecognizedDocument.fromJson({
  'doc_type': kind, 'image_width': 1000, 'image_height': 1000,
  'blocks': [for (var i=0; i<rows.length; i++) {
    'text': rows[i], 'page': 0,
    'box': {'x': 20, 'y': 40+i*80, 'width': 700, 'height': 40},
  }],
});

void main() {
  test('read-only receipts do not instruct unnecessary retakes or signatures', () {
    final document=doc('receipt', ['영수증','결제 금액: 10000원','상호: 가상문구']);
    final targets=findFillTargets(document);
    expect(targets,isEmpty);
    expect(describeFillTargets(targets),isNot(contains('다시 찍어')));
    expect(describeSignatureSpots(findSignatureSpots(document)),isNot(contains('다시 찍어')));
  });
  test('survey yes/no question is read as its question rather than consent', () {
    for(final rows in [
      ['시설에 만족하십니까? □예 □아니요'],
      ['시설에 만족하십니까?', '□예 □아니요'],
    ]) {
      final target=findFillTargets(doc('questionnaire', rows)).single;
      expect(target.kind,FillKind.check);
      expect(target.shortName,'응답');
      expect(checkQuestion(target),'시설에 만족하십니까?');
      expect(checkQuestion(target),isNot(contains('동의')));
      final block=findCheckBlock(target,doc('questionnaire',rows).blocks);
      expect(block,isNotNull);
      expect(checkBoxRects(target,block!),isNotNull);
    }
  });
  test('privacy consent within a survey retains consent semantics', () {
    final target=findFillTargets(doc('questionnaire', ['개인정보 수집에 동의하십니까? □예 □아니요'])).single;
    expect(target.shortName,'동의');
    expect(checkQuestion(target),contains('개인정보'));
  });
  test('unreadable surveys do not produce response targets', () {
    final payload=doc('questionnaire',['시설에 만족하십니까? □예 □아니요']).toJson();
    payload['needs_review']=true;
    expect(findFillTargets(RecognizedDocument.fromJson(payload)),isEmpty);
  });
}

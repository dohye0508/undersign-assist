import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/features/fill/fill_kind.dart';
import 'package:undersign_assist/features/fill/fill_targets.dart';
import 'package:undersign_assist/models/recognized_document.dart';

/// 배포된 서버(Debian Tesseract)가 실제로 읽은 줄들. 노트북 Windows Tesseract와 □ 읽는 방식이 달라서
/// 상자가 "더", "던" 같은 한글 한 글자로 나온다 (2026-10-25 동의 칸이 안 잡힌 원인)
RecognizedDocument _load(String name) =>
    RecognizedDocument.fromJson(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

List<String> _checks(RecognizedDocument doc) =>
    [for (final t in findFillTargets(doc)) if (t.kind == FillKind.check) t.label];

void main() {
  test('상자를 한글로 잘못 읽어도(ㅁ예 더아니요) 동의 칸 둘이 잡힌다', () {
    expect(_checks(_load('ocr_school_deployed')), ['수집·이용 동의 여부', '제3자 제공 동의 여부']);
  });

  test('인곽 서식도 마찬가지', () {
    expect(_checks(_load('ocr_ingwak_deployed')), ['수집·이용 동의 여부', '제3자 제공 동의 여부']);
  });

  test('상자가 글자 뒤에 오는 서식(예 □ 아니요 □): 물음은 윗줄, 보호자 칸은 제목으로 구분', () {
    expect(_checks(_load('ocr_hackathon_deployed')), ['수집·이용 동의 여부', '보호자 수집·이용 동의 여부']);
  });

  test('예 상자는 아니요 상자보다 왼쪽이고 둘 다 사진 안에 있다', () {
    for (final name in ['ocr_school_deployed', 'ocr_hackathon_deployed']) {
      final doc = _load(name);
      final checks = findFillTargets(doc).where((t) => t.kind == FillKind.check);
      expect(checks, isNotEmpty);
      for (final t in checks) {
        final block = findCheckBlock(t, doc.blocks);
        expect(block, isNotNull, reason: '$name ${t.label} 줄을 못 찾음');
        final boxes = checkBoxRects(t, block!)!;
        expect(boxes.yes.center.dx, lessThan(boxes.no.center.dx), reason: '$name ${t.label}');
        expect(boxes.yes.left, greaterThanOrEqualTo(0));
        expect(boxes.no.right, lessThanOrEqualTo(doc.imageWidth + 1));
      }
    }
  });
}

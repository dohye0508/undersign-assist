# 서식 경계와 복합 촬영 OCR 시험

12개 직접 작성한 문서 묶음 × 5조건 = 60건/85장. 합성 시험 자료이며 실제 현장 사진이 아닙니다.
정면, 책상, 손에 든 촬영의 기울기·그림자·축소·압축, 어두운 화면, 판독 불가 축소를 시험합니다.
실제 OCR을 저장한 뒤 동일 원문으로 이전/현재 코드의 분류와 항목 추출을 비교합니다. OCR 엔진 자체는 바꾸지 않았습니다.

```json
{
  "documents": 60,
  "images": 85,
  "ordinary_before_correct": 33,
  "ordinary_correct": 47,
  "ordinary": 48,
  "negative_detected": 12,
  "negatives": 12,
  "gate_failures": 5,
  "field_correct": 75,
  "before_field_correct": 35,
  "field_checks": 84,
  "ordinary_character_edit_rate": 0.0391,
  "by_profile": {
    "clean": {
      "documents": 12,
      "class_correct": 12,
      "review_expected": 11,
      "field_correct": 20,
      "field_checks": 21
    },
    "desk": {
      "documents": 12,
      "class_correct": 12,
      "review_expected": 11,
      "field_correct": 20,
      "field_checks": 21
    },
    "handheld": {
      "documents": 12,
      "class_correct": 11,
      "review_expected": 11,
      "field_correct": 15,
      "field_checks": 21
    },
    "dark_screen": {
      "documents": 12,
      "class_correct": 12,
      "review_expected": 11,
      "field_correct": 20,
      "field_checks": 21
    },
    "tiny_unreadable": {
      "documents": 12,
      "class_correct": null,
      "review_expected": 12,
      "field_correct": 0,
      "field_checks": 0
    }
  }
}
```

항목값은 지정한 일부 값만 비교하며 부호·숫자는 그대로, 공백만 제거합니다. 누락/오인식도 모두 실패로 기록합니다.
문자 편집률은 일반 조건의 원문/OCR에서 공백·문장부호를 제외한 편집 거리 ÷ 원문 글자 수입니다. 분류 정확도와 별도 지표입니다.

|사례|정답|이전→현재|재촬영|분류·품질 검사|지정 값|
|---|---|---|---|---|---|
|cover_lists_titles/clean|authorization|unknown→authorization|True|False|0/0|
|cover_lists_titles/desk|authorization|authorization→authorization|True|False|0/0|
|cover_lists_titles/handheld|authorization|unknown→authorization|True|False|0/0|
|cover_lists_titles/dark_screen|authorization|unknown→authorization|True|False|0/0|
|cover_lists_titles/tiny_unreadable|authorization|unknown→unknown|True|True|0/0|
|split_reference_appendix/clean|authorization|unknown→authorization|False|True|0/0|
|split_reference_appendix/desk|authorization|unknown→authorization|False|True|0/0|
|split_reference_appendix/handheld|authorization|unknown→unknown|False|False|0/0|
|split_reference_appendix/dark_screen|authorization|unknown→authorization|False|True|0/0|
|split_reference_appendix/tiny_unreadable|authorization|unknown→unknown|True|True|0/0|
|unsupported_primary_with_privacy/clean|unknown|consent→unknown|False|True|0/0|
|unsupported_primary_with_privacy/desk|unknown|consent→unknown|False|True|0/0|
|unsupported_primary_with_privacy/handheld|unknown|consent→unknown|False|True|0/0|
|unsupported_primary_with_privacy/dark_screen|unknown|consent→unknown|False|True|0/0|
|unsupported_primary_with_privacy/tiny_unreadable|unknown|unknown→unknown|True|True|0/0|
|clinical_form_is_not_school_reply_appendix/clean|unknown|notice→unknown|False|True|0/0|
|clinical_form_is_not_school_reply_appendix/desk|unknown|notice→unknown|False|True|0/0|
|clinical_form_is_not_school_reply_appendix/handheld|unknown|notice→unknown|False|True|0/0|
|clinical_form_is_not_school_reply_appendix/dark_screen|unknown|notice→unknown|False|True|0/0|
|clinical_form_is_not_school_reply_appendix/tiny_unreadable|unknown|unknown→unknown|True|True|0/0|
|inline_contract/clean|contract|contract→contract|False|True|4/4|
|inline_contract/desk|contract|contract→contract|False|True|4/4|
|inline_contract/handheld|contract|contract→contract|False|True|3/4|
|inline_contract/dark_screen|contract|contract→contract|False|True|4/4|
|inline_contract/tiny_unreadable|contract|unknown→unknown|True|True|0/0|
|inline_application/clean|application|application→application|False|True|3/4|
|inline_application/desk|application|application→application|False|True|3/4|
|inline_application/handheld|application|application→application|False|True|0/4|
|inline_application/dark_screen|application|application→application|False|True|3/4|
|inline_application/tiny_unreadable|application|unknown→unknown|True|True|0/0|
|inline_receipt/clean|receipt|receipt→receipt|False|True|2/2|
|inline_receipt/desk|receipt|receipt→receipt|False|True|2/2|
|inline_receipt/handheld|receipt|receipt→receipt|False|True|2/2|
|inline_receipt/dark_screen|receipt|receipt→receipt|False|True|2/2|
|inline_receipt/tiny_unreadable|receipt|unknown→unknown|True|True|0/0|
|inline_certificate/clean|certificate|certificate→certificate|False|True|3/3|
|inline_certificate/desk|certificate|certificate→certificate|False|True|3/3|
|inline_certificate/handheld|certificate|certificate→certificate|False|True|3/3|
|inline_certificate/dark_screen|certificate|certificate→certificate|False|True|3/3|
|inline_certificate/tiny_unreadable|certificate|unknown→unknown|True|True|0/0|
|night_contract/clean|contract|contract→contract|False|True|2/2|
|night_contract/desk|contract|contract→contract|False|True|2/2|
|night_contract/handheld|contract|contract→contract|False|True|2/2|
|night_contract/dark_screen|contract|contract→contract|False|True|2/2|
|night_contract/tiny_unreadable|contract|unknown→unknown|True|True|0/0|
|weekday_contract/clean|contract|contract→contract|False|True|2/2|
|weekday_contract/desk|contract|contract→contract|False|True|2/2|
|weekday_contract/handheld|contract|contract→contract|False|True|2/2|
|weekday_contract/dark_screen|contract|contract→contract|False|True|2/2|
|weekday_contract/tiny_unreadable|contract|unknown→unknown|True|True|0/0|
|party_contacts/clean|authorization|authorization→authorization|False|True|2/2|
|party_contacts/desk|authorization|authorization→authorization|False|True|2/2|
|party_contacts/handheld|authorization|authorization→authorization|False|True|1/2|
|party_contacts/dark_screen|authorization|authorization→authorization|False|True|2/2|
|party_contacts/tiny_unreadable|authorization|unknown→unknown|True|True|0/0|
|signed_amount/clean|receipt|receipt→receipt|False|True|2/2|
|signed_amount/desk|receipt|receipt→receipt|False|True|2/2|
|signed_amount/handheld|receipt|receipt→receipt|False|True|2/2|
|signed_amount/dark_screen|receipt|receipt→receipt|False|True|2/2|
|signed_amount/tiny_unreadable|receipt|unknown→unknown|True|True|0/0|

재현: `python backend/tests/boundary_ocr_samples.py ocr` → `evaluate` → `report`. 이미지 변경 시에만 `generate`.
`evaluate --require-correct`는 종류·재촬영·좌표 오류가 하나라도 남으면 실패합니다. 기본 evaluate는 실패도 기록하는 측정입니다. 항목값 오류는 별도 수치이며 전체 인식 정확도가 아닙니다.
CI에서는 기존 OCR 검증 조건을 유지하고, 새 60건을 실패 포함 측정하여 별도 artifact로 보존합니다. 이 측정 단계의 종료 코드 0이 모든 OCR 값의 성공을 뜻하지 않습니다.

# 추가 검토 실제 OCR 표본

가상 문서 5묶음 × 정면/5도 기울기 = 10건, 이미지 16장. 현장 사진이 아닙니다.
저장한 이미지 해시를 확인하고 실제 Tesseract를 실행했습니다. 같은 OCR 결과로 이전/현재 분류를 비교합니다.

|사례|정답|이전|현재|재촬영|지정 항목값|
|---|---|---|---|---|---|
|privacy_appendix/clean [사진1](images/privacy_appendix/clean-1.jpg) · [사진2](images/privacy_appendix/clean-2.jpg)|authorization|consent|authorization|False|0/0|
|privacy_appendix/skew [사진1](images/privacy_appendix/skew-1.jpg) · [사진2](images/privacy_appendix/skew-2.jpg)|authorization|consent|authorization|False|0/0|
|mixed_cropped/clean [사진1](images/mixed_cropped/clean-1.jpg) · [사진2](images/mixed_cropped/clean-2.jpg)|unknown|authorization|unknown|False|0/0|
|mixed_cropped/skew [사진1](images/mixed_cropped/skew-1.jpg) · [사진2](images/mixed_cropped/skew-2.jpg)|unknown|authorization|unknown|False|0/0|
|reference_appendix/clean [사진1](images/reference_appendix/clean-1.jpg) · [사진2](images/reference_appendix/clean-2.jpg)|unknown|invoice|unknown|False|0/0|
|reference_appendix/skew [사진1](images/reference_appendix/skew-1.jpg) · [사진2](images/reference_appendix/skew-2.jpg)|unknown|unknown|unknown|False|0/0|
|certificate_subject/clean [사진1](images/certificate_subject/clean-1.jpg)|certificate|certificate|certificate|False|2/2|
|certificate_subject/skew [사진1](images/certificate_subject/skew-1.jpg)|certificate|certificate|certificate|False|2/2|
|applicant_contact/clean [사진1](images/applicant_contact/clean-1.jpg)|application|application|application|False|2/2|
|applicant_contact/skew [사진1](images/applicant_contact/skew-1.jpg)|application|application|application|False|2/2|

분류·재촬영·지정 항목값 조건 중 불일치한 사례: 0/10. OCR 원문은 results.json에 보존했습니다.

저장된 이미지 그대로 재현: `python backend/tests/review_round2_samples.py evaluate --require-correct`. 문안 변경 시에만 `generate`로 재생성합니다.

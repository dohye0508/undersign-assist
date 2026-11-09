# 문서 종류 확장 실제 OCR 검증

24개 직접 작성한 가상 문서 문안 × 8조건 = 192장입니다. 합성 변형이며 실제 현장 사진 192장이 아닙니다.
조건: 원본, 5도 기울기, 책상 배경, 그림자, 흐림, 제목 잘림, 90도 회전, 판독 불가 저해상도.
Tesseract를 실제 실행해 저장한 동일 OCR 블록을 이전/현재 분류기에 전달했습니다. OCR 엔진 자체의 향상을 측정하는 비교가 아닙니다.
이전 코드: `7263d75a1c259d6139614a198835a3ed4a16f17f`. 엔진: `tesseract v5.5.0.20241111`. API/LLM 호출 없음.

- 일반 사진 분류: 0/168 → 168/168
- 분류 일치 + 재촬영 불필요: 168/168
- 분류 일치 + 하나 이상 항목 추출: 168/168 (값 전체의 정확도 지표는 아님)
- 문서당 2개 지정 항목값 표본 확인: 327/336 (공백·문장부호 제거 후 비교, 전체 항목 정확도는 아님)
- 판독 불가 사진 재촬영 처리: 24/24
- 좌표 범위 오류: 0

|종류|일반 사진|이전 분류|현재 분류|재촬영 없이 진행|
|---|---:|---:|---:|---:|
|활동 참가 동의서 (activity_consent)|21|0|21|21|
|위임장 (authorization)|21|0|21|21|
|확인·증명서 (certificate)|21|0|21|21|
|청구서·고지서 (invoice)|21|0|21|21|
|서약서 (pledge)|21|0|21|21|
|설문지 (questionnaire)|21|0|21|21|
|영수증 (receipt)|21|0|21|21|
|보고서 (report)|21|0|21|21|

## 분류·재촬영·좌표 실패

없음. 이 고정된 합성 표본 안에서의 결과입니다.

## 지정 항목값 불일치

- [invoice_1/blur](images/invoice_1/blur.jpg): 납부 기한
- [invoice_2/clean](images/invoice_2/clean.jpg): 납부 기한
- [invoice_2/blur](images/invoice_2/blur.jpg): 납부 기한
- [invoice_2/cropped_title](images/invoice_2/cropped_title.jpg): 납부 기한
- [invoice_3/skew](images/invoice_3/skew.jpg): 납부 기한
- [invoice_3/desk](images/invoice_3/desk.jpg): 납부 기한
- [pledge_2/desk](images/pledge_2/desk.jpg): 작성일
- [questionnaire_3/skew](images/questionnaire_3/skew.jpg): 의견
- [activity_consent_3/skew](images/activity_consent_3/skew.jpg): 활동명

## 재현

저장소 루트에서:
```powershell
backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py generate
backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py ocr
backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py evaluate
backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py report
```

manifest.json은 이미지 해시/기대 종류/문안/조건을, ocr.json은 실제 인식 글자·좌표·신뢰도·엔진 정보를 저장합니다.
results.json은 같은 OCR 결과에 대한 전후 분류와 항목 추출값입니다. index.html에서 조건별 사진과 결과를 비교할 수 있습니다.
문안과 변형을 구현 중 사용한 개발 표본이며 독립 외부 평가가 아닙니다. 손글씨, 심한 가림, 모든 서식·촬영 장치를 검증하지 않았습니다.

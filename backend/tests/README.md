# 문서 분류 회귀 시험

분류는 OCR **이후**에 실행된다. 이 시험은 문서 종류와 뒤따르는 항목 추출·판단의 연결을 검증한다. 법률 기준이나 법령 데이터는 변경하지 않는다.

## 표본

- `fixtures/document_cases.json`: 사람이 작성한 가상 한국어 서식 85개. 계약·임대차·차용증, 개인정보 동의, 가정통신문, 신청, 작품 요약, 알 수 없는 문서를 포함한다. 제목만 남은 문서, 개인정보 부록, 단어 반복, 교육자료·처리방침·수술 동의서도 구분한다.
- `fixtures/document_ocr.json`: 저장소 `samples/` 사진 9개를 2026-10-29 로컬 Tesseract 5.5.0 한국어 모델과 기존 두 번 읽기 코드로 인식한 결과. 원본 파일 경로와 줄·좌표·페이지를 기록했다. `consent_school.png`와 `인곽.png`는 같은 양식이며 독립 표본으로 해석하면 안 된다.
- `app/test/fixtures/ocr_*_deployed.json`: 기존 배포 서버 OCR 3개. 깨진 글자와 누락된 표 머리글을 그대로 사용한다. 로컬 사진과 양식이 겹친다.
- 각 표본에 원문, 글자 사이 공백, NFD 한글, 보이지 않는 문자·구분자, 세 번 중복한 페이지를 적용한다. **97개 입력 × 5개 변형 = 485건**이며 서로 독립적인 485개 문서는 아니다.

## 실행

저장소 루트에서 백엔드 가상 환경의 Python을 사용한다. 정규 회귀 시험에는 Tesseract 실행 파일·네트워크·API 키가 필요 없다.

```sh
python -m unittest discover -s backend/tests -p "test_*.py" -v
python backend/tests/evaluate_documents.py --failures
python backend/tests/smoke_judge.py
```

평가 결과를 파일로 남기거나 같은 표본의 이전 결과와 비교할 수 있다.

```sh
python backend/tests/evaluate_documents.py --output work/current.json
python backend/tests/evaluate_documents.py --baseline work/baseline.json
```

Tesseract와 `kor.traineddata`가 있으면 합성 이미지 18개를 넓은 배치·좁은 배치로 각각 만든 뒤 실제 OCR을 거치는 36건도 실행한다. 사진은 메모리에만 생성한다. `--all`은 작성한 85개 사례 전체를 이미지로 시험하는 탐색용 옵션이며 OCR 엔진 버전에 따라 결과가 달라질 수 있다.

```sh
python backend/tests/smoke_ocr_documents.py --output work/ocr-evaluation.json
```

## 2026-10-29 비교

수정 전 기준은 커밋 `759f54a`의 `doc_reader.py`와 `doc_types.json`이다. 두 실행 모두 AI를 끄고 같은 표본을 사용했다.

| 구분 | 기존 | 변경 후 |
|---|---:|---:|
| 작성한 텍스트 | 48/85 | 85/85 |
| 로컬 사진 OCR | 9/9 | 9/9 |
| 배포 OCR 기록 | 3/3 | 3/3 |
| 원문 전체 | 60/97 | 97/97 |
| 변형 포함 | 228/485 | 485/485 |
| 새 서식 이미지의 실제 OCR | 측정하지 않음 | 36/36 |

이 표본은 발견한 오류를 재현하고 수정하는 데 사용한 **회귀용 개발 자료**다. 별도 검증 세트나 실제 서비스 정확도 측정치가 아니다. 손글씨, 심한 기울어짐, 저조도, 처음 보는 양식에서의 정확도는 별도 수집·검증이 필요하다. 실제 Groq 호출은 하지 않았으며, 정상 응답·다른 종류·잘못된 JSON 구조·통신 실패를 모의 응답으로 검증했다.

## 규칙 수정

`backend/app/rules/doc_types.json`의 `classification`을 수정한다.

- `titles`: 첫 페이지 앞부분에서 제목으로 인정하는 표현.
- `groups`: 같은 의미의 표현 묶음. 여러 번 나오거나 동의어가 겹쳐도 묶음당 한 번만 센다.
- `required_all` / `required_any`: 제목 없이 본문으로 분류할 때 필요한 근거.
- `min_groups`: 제목 없는 문서에서 필요한 최소 근거 묶음 수.

`type_scores`는 제목 10점과 근거 묶음당 2점을 더한 진단 값이다. 출현 횟수나 확률이 아니며, 혼합 서식 분기 때문에 최고 점수 종류와 최종 종류가 다를 수 있다. 기존 API의 자료형과 종류 이름은 유지한다. `DocumentClassifier.classify()`의 `reason`으로 분기 이유를 확인할 수 있다.

제목이 둘 이상 충돌하거나 본문 근거 점수가 같은 경우 `unknown`으로 남긴다. 짧은 개인정보 문구가 있다고 주 문서 종류를 바꾸지 않는다. 의료·행사 참가 동의는 개인정보 동의와 별개이며, 현재 지원하지 않는 종류는 `unknown`으로 남긴다.

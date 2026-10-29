# OCR 재현 샘플

`samples/index.html`을 브라우저에서 열면 사진·촬영 조건·정답·개선 전후 OCR 본문을 함께 볼 수 있습니다. 서버나 외부 API가 필요하지 않습니다. 검색, 조건 선택, 개선 후 실패 필터를 제공합니다.

## 원본과 파생 이미지

기존 원본 9개는 이 폴더에 보존했습니다. `consent_school.png`와 `인곽.png`는 같은 이미지이므로 평가에는 한 번만 포함합니다. 파일 이름이 문서 종류와 다른 경우가 있습니다. `한국코드페어 해커톤 참가신청서.png`는 신청서 제목 아래 개인정보 동의 내용만 있는 페이지이므로 정답은 `consent`입니다.

| 폴더 | 이미지 수 | 내용 |
|---|---:|---|
| `regression/camera` | 240 | 기존 가상 문서 16개 × 기본 촬영 조건 15가지 |
| `regression/development` | 66 | 개발용 내용 6개 × 복합 장면 11가지 |
| `regression/holdout` | 110 | 내용이 다른 문서 10개 × 복합 장면 11가지 |
| `regression/originals` | 64 | 중복을 뺀 저장소 원본 8개 × 변형 8가지 |
| `regression/everyday_text` | 128 | 가상 문서 16개 × 추가 상황 8가지 |
| `regression/everyday_originals` | 48 | 저장소 원본 8개 × 추가 상황 6가지 |
| 합계 | **656** | 읽을 수 없는 대조군 48장 포함 |

`regression/manifest.json`에 각 이미지의 출처, 촬영 조건, 생성 시드, 크기, SHA-256, 종류 정답, 재촬영 기대 여부, 가능한 경우 원문을 저장합니다. 파일 경로는 ASCII로 만들었으며 한글 원본 파일 이름은 manifest에 남겼습니다. `original_01`부터 차례로 동의서, 계약서, 작성된 계약서, 통신문, 인천과학고 동의서, 빈 작품요약서, 참가신청서２, 코드페어 개인정보 동의 페이지입니다.

모두 **가상 문서 또는 저장소 예시를 프로그램으로 변형한 이미지**입니다. 손가락 모양·펜 표시도 합성입니다. `holdout`은 개발 묶음과 내용·시드가 다르다는 뜻이며 외부 독립 현장 자료는 아닙니다. 종류 분류 성공이 본문 전체의 정확한 인식을 뜻하지는 않습니다.

## 촬영 조건

- 기본: 회전, EXIF, 낮은 해상도, 흔들림, 그림자, 원근, JPEG 압축, 표 선, 제목 잘림, 노이즈.
- 복합: 큰 기울기, 손에 들고 촬영한 상태의 원근·그림자·축소·압축, 책상 배경, 두 단, 회색 표, 어두운 화면, 화면 줄무늬, 접힌 자국, 펜 표시.
- 추가: 문서보다 넓은 책상 여백(`distant_desk`), 회전과 기울기가 함께 있는 책상 사진(`sideways_desk`), 여백의 손가락(`finger_margin`), 흐린 복사본(`faded_copy`), 방향성 흔들림(`motion_blur`), 강한 그림자(`hard_shadow`).
- 실패 대조군: 본문 흐림(`body_blurred`), 본문이 사라진 반사광(`body_glare`), 극단적인 축소·흐림(`tiny_unreadable`). 재촬영을 요청해야 성공입니다.

일부 내용이 손이나 물체에 완전히 가려진 경우, 임의 손글씨, 곡면·심한 원근, 실제 여러 기종의 카메라를 모두 검증한 것은 아닙니다. 남은 실패도 결과와 목록에 유지합니다.

## 다시 실행

저장소 루트에서 Tesseract 한국어 데이터와 `backend/requirements.txt`를 설치한 Python으로 실행합니다. Windows 가상환경은 `backend\.venv\Scripts\python.exe`를 사용하면 됩니다.

```sh
# 이미 저장한 이미지 바이트 그대로 읽어 평가. 해시가 다르면 중단합니다.
python backend/tests/sample_corpus.py evaluate --suites originals everyday_originals everyday_text --output work/recheck.json

# 빈 표 한 종류만 선택
python backend/tests/sample_corpus.py evaluate --suites originals --cases 작품요약서.png --profiles clean desk tilted --require-correct --output work/blank-form.json

# 변경 전 구현과 비교 (신뢰하는 로컬 커밋만 지정)
python backend/tests/sample_corpus.py evaluate --baseline-ref 6063a33 --output work/baseline.json

# 생성기나 원본을 바꿨을 때만 이미지와 manifest를 명시적으로 재생성
python backend/tests/sample_corpus.py generate

# results/before*.json, after*.json을 목록에 반영
python backend/tests/sample_corpus.py catalog
```

평가 기본 모드는 실패를 포함해 기록합니다. `--require-correct`를 붙이면 종류 오류, 정상 사진의 불필요한 재촬영 요청, 실패 대조군 통과, 좌표 범위 오류 중 하나라도 있으면 실패합니다. 읽은 글자가 기호뿐인 경우도 재촬영 대상입니다.

새 업로드 문서는 이 폴더에 저장되지 않습니다. 이 폴더는 재현 가능한 시험용 자료만 관리합니다.

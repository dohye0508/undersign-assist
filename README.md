# 들리는계약서 (undersign-assist)

시각장애인이 **종이 문서**를 혼자 읽고, 판단하고, 쓰고, 서명할 수 있게 돕는 앱입니다. 한국코드페어 해커톤 출품작입니다.

- 앱: https://dohye0508.github.io/undersign-assist/
- 백엔드: https://undersign-assist-api.onrender.com (무료 호스팅이라 처음 요청은 깨어나는 데 50초쯤 걸릴 수 있습니다)

앱을 켜면 카메라가 바로 켜집니다. 계약서, 가정통신문, 개인정보 동의서 같은 종이 문서를 한 장씩 찍거나 사진으로 불러온 뒤 분석하면, 모든 페이지를 한 문서로 읽고 음성으로 안내합니다. 사용자는 화면을 볼 수 없다고 가정하므로 모든 결과는 음성으로 전하고, 화면 표시는 보조입니다.

## 네 단계

실제로 쓰는 순서대로입니다. 판단 없이 서명하게 만들지 않으려고 판단을 서명보다 앞에 둡니다.

| 단계 | 하는 일 |
|---|---|
| 읽기 | 글자와 위치를 인식하고, 문서 종류를 알아내고, 핵심 항목을 뽑아 "요약 듣기", "전체 듣기"로 읽어 줍니다 |
| 검토하세요! (판단) | 법령 데이터(근로기준법, 최저임금법, 주택임대차보호법, 개인정보 보호법 등)와 견주어 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려 줍니다 |
| 쓰고 서명하기 | 써야 할 칸(성명, 날짜, 예/아니요 체크, 서명)을 음성으로 하나씩 안내합니다. 안드로이드 태블릿에 펜으로 쓰고 왼쪽으로 밀면, 글씨가 문서 사진의 그 자리로 들어갑니다 |
| 출력 | 글씨와 서명을 합성한 PDF를 내려받습니다 |

**들리는 받아쓰기**: 촬영 화면의 "글씨 연습하기" 버튼(또는 설정 → 들리는 받아쓰기)으로 들어갑니다. 계약서에 쓰기 전에 태블릿에서 자음·모음·글자·낱말을 회색 보조선을 따라 써 보는 연습입니다. 보조선에 가까울수록 진동이 촘촘해지고, 다 쓰면 점수와 고칠 점 하나를 음성으로 알려 줍니다. 이름·주소·생년월일·전화번호를 등록해 두면 그 낱말로 연습할 수 있고, 쓰고 서명하기에서도 본인 칸에 회색 보조 글씨로 깔립니다. 등록한 정보와 점수는 기기 브라우저에만 저장됩니다.

## 원칙

- **AI는 읽기만 합니다.** 판단(계산과 판정)은 규칙과 수식이 합니다. 법 기준 값(최저임금 등)은 공식 자료에서 확인해 데이터 파일로 따로 두었습니다.
- **단정하지 않습니다.** 결과는 "~로 보여요, 확인이 필요해요"처럼 말하고, 문서 원문 문장과 비교 기준을 함께 줍니다. 법률 자문이 아닙니다.
- **읽어 줄 문장은 코드가 만듭니다.** AI에게 요약 문장을 맡겼더니 문서에 없는 내용을 지어내서, 문장은 뽑은 항목으로 만듭니다.
- **사진은 남기지 않습니다.** 백엔드는 받은 사진을 메모리에서만 처리합니다.
- **모든 버튼은 짧은 진동과 딸깍 소리**를 냅니다. 진동은 안드로이드 크롬에서만 나므로 소리와 음성을 항상 함께 냅니다.
- 말하기 속도, 말소리·효과음 크기, 진동은 설정 화면에서 바꿉니다.

## 동작 방식

- **글자 인식** (`backend/app/services/ocr.py`): 기본은 Tesseract 한국어(키·인터넷 없이 동작)입니다. 그림자와 낮은 대비를 보정하고, 보통 두 번 읽어(psm 6, psm 11) 신뢰도가 낮은 줄만 바꿉니다. 첫 인식이 불확실할 때만 90·180·270도 방향을 추가로 확인합니다(총 최대 5회). 읽는 순서를 유지하면서 좌표는 원본 사진으로 되돌리므로 서명·쓰기 위치를 그대로 사용할 수 있습니다. `OCR_PROVIDER=google`이면 Google Cloud Vision을 씁니다(손글씨에 더 정확).
- **문서 종류·항목** (`services/doc_classifier.py`, `services/doc_reader.py`, `rules/doc_types.json`): OCR 후 첫 페이지 제목과 서로 다른 본문 근거를 함께 보고 계약서, 가정통신문, 개인정보 동의서, 신청서, 요약서를 구분합니다. 반복 단어·중복 페이지는 점수를 늘리지 않으며, 근거가 부족하거나 충돌하면 종류를 단정하지 않습니다. 근로계약 외에 임대차·차용증·서비스 계약의 근거도 포함합니다. 작성 칸이 있는 본문에 붙은 개인정보 동의서는 원래 종류를 유지하고, 제목만 신청서·통신문인 개인정보 중심 서식은 동의서로 구분합니다. 종류를 정한 뒤 `GROQ_API_KEY`가 있으면 AI(Groq)가 항목을 옮겨 적고, 없거나 실패하거나 종류를 바꾸면 규칙 추출로 돌아갑니다.
- **판단** (`services/judge/`, `rules/laws/`): 필수 기재 누락, 숫자 비교, 무효 특약 키워드, 안내 규칙. 사업장 규모처럼 답에 따라 결과가 바뀌는 경우에만 결과보다 먼저 질문합니다. 법령 데이터의 출처와 다시 만드는 법은 [backend/app/rules/laws/README.md](backend/app/rules/laws/README.md)에 있습니다.
- **칸 찾기** (`app/lib/features/fill/`): 읽기 결과에서 "성명:", "(서명)", "년 월 일", "□예 □아니요" 같은 빈칸을 찾습니다. 날짜는 연·월·일을 따로 받습니다. 글씨 품질은 획 수·크기·시간으로만 검사합니다(AI 안 씀).
- **받아쓰기 판정** (`app/lib/features/practice/`): 목표 글자를 도현체로 그려 거리 지도를 만들고, 펜 좌표로 모양·크기·위치·기울기·자간을 잽니다.

## 구조

```
app/                    Flutter 앱 (웹으로 실행)
  lib/screens/          화면 하나 (workspace_screen: 촬영 ↔ 분석)
  lib/features/         read, judge, fill, write, sign, output, practice(받아쓰기), settings
  lib/models/           사진, 읽기 결과, 판단 결과, 공유 상태 (백엔드 app/models.py와 모양을 맞춤)
  lib/services/         백엔드 호출, 카메라, 음성, 진동·소리, 내려받기
  lib/widgets/          공통 위젯, 로고, 시작 화면
  lib/theme/            색과 글꼴 (app_theme.dart 한 곳에서만 정의)
  test/                 단위 시험 (칸 찾기는 배포 서버가 실제로 읽은 OCR 결과로 시험)
backend/                FastAPI 서버
  app/routers/          read, judge, write, sign
  app/services/         ocr, doc_reader, llm, judge/
  app/rules/            문서 종류 규칙, 판단 하위 유형, laws/ 법령 DB
  tests/smoke_judge.py  판단 엔진 시험
samples/                시험·시연용 가짜 문서 사진 (실제 개인정보 없음)
  index.html            저장된 시험 사진·정답·개선 전후 OCR 비교 목록
  regression/           조건별 재현 이미지 656장, manifest, 측정 결과
scripts/                패드 모드 서버, 인증서, 웹 아이콘 만들기
```

## 실행

백엔드 (글자 인식에 Tesseract와 한국어 데이터 `kor.traineddata`가 필요합니다):

```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

앱 (다른 터미널):

```
cd app
flutter pub get
flutter run -d chrome
```

- 서버는 `127.0.0.1`에만 묶습니다(`--host 0.0.0.0` 금지). 대회장처럼 같은 와이파이에 다른 사람이 있을 수 있기 때문입니다.
- 카메라는 `localhost`나 HTTPS에서만 열립니다.
- 백엔드 주소를 바꾸려면 `flutter run -d chrome --dart-define=API_BASE=http://주소:포트`.
- 설정 값(`OCR_PROVIDER`, `TESSERACT_CMD`, `GROQ_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`)은 `backend/.env`에 둡니다. 이름은 `backend/.env.example`에 있습니다. **`.env`와 키 파일은 절대 커밋하지 않습니다.**
- 빌드 후 브라우저가 옛 화면을 보여 주면 강력 새로고침(Ctrl+Shift+R)합니다.
- Windows에서 `uvicorn --reload`가 변경을 못 잡으면 서버를 껐다 켭니다.

시험:

```
python backend/tests/smoke_judge.py
python -m unittest discover -s backend/tests -p "test_*.py" -v
python backend/tests/evaluate_documents.py
cd app
flutter test
```

문서 분류 시험은 처음 작성한 85개 사례, 추가 일반 서식 48개, 기존 사진 OCR 9개, 배포 OCR 3개를 사용합니다. 공백·유니코드·중복 페이지 변형까지 725건을 확인하며, AI 응답 오류·혼합 문서·여러 페이지 연결·회전 좌표도 시험합니다. 구성과 측정 결과는 `backend/tests/README.md`에 있습니다. GitHub Actions에서 단위 시험과 실제 OCR 103건을 실행합니다. `samples/index.html`에는 재현 이미지 656장과 전후 결과를 정리했습니다.

Tesseract와 한국어 데이터가 설치된 환경에서는 새 서식 18개를 두 가지 이미지 배치로 렌더링해 실제 OCR도 시험할 수 있습니다. 사진과 AI API를 외부로 보내지 않습니다.

```
python backend/tests/smoke_ocr_documents.py
python backend/tests/stress_ocr_documents.py --output work/camera.json
```

두 번째 명령은 다른 내용의 가상 문서 16개에 흐림, 그림자, 기울어짐, 원근, 저해상도, 압축, 표, 90·180·270도 회전, EXIF, 제목 잘림, 노이즈 등 15가지 조건을 적용하는 240건의 실제 OCR 시험입니다. 작성 안내서와 실제 서식, 개인정보 부록과 서로 다른 문서 묶음도 별도로 확인합니다. 모든 현실 조건을 검증한 것은 아니며, 합성 이미지 결과와 실제 서비스 정확도는 구분합니다.

## 배포

| 무엇 | 어떻게 |
|---|---|
| 앱 | `main`에 `app/` 변경을 푸시하면 `.github/workflows/pages.yml`이 GitHub Pages로 자동 배포합니다. 백엔드 주소는 저장소 변수 `API_BASE` |
| 백엔드 | Render 무료(`render.yaml`, `backend/Dockerfile`). 자동 배포가 없으니 `backend/`를 고치면 Render 대시보드 → Manual Deploy. `GROQ_API_KEY`는 Render 환경 변수에만 둡니다 |

- Render 무료는 15분 쉬면 잠듭니다. `.github/workflows/keep-awake.yml`이 10분마다 깨우지만, 시연 직전에는 `/api/health`를 직접 한 번 엽니다.
- 사진 한 장 분석에 배포 서버는 13~32초, 노트북은 5초쯤 걸립니다.

### 패드 모드 (배포 주소를 못 쓸 때)

같은 와이파이의 안드로이드 태블릿에서 노트북 서버를 HTTPS로 엽니다. **127.0.0.1 규칙의 유일한 예외**라 시연 중에만 씁니다.

```
powershell -ExecutionPolicy Bypass -File scripts/pad-serve.ps1
powershell -ExecutionPolicy Bypass -File scripts/pad-stop.ps1
```

자체 서명 인증서라 패드 크롬에서 **먼저** `https://<ip>:8443/api/health`의 경고를 통과한 뒤 `https://<ip>:3443`을 엽니다. 접속이 안 되면 스크립트가 출력하는 방화벽 명령을 관리자 PowerShell에서 실행하고, 시연 후 지웁니다.

## 한계

- 서류 위조 판별, 상대방 신원 확인, 실시간 권리관계 확인은 할 수 없습니다.
- Tesseract는 인쇄 글자는 잘 읽지만 손글씨에는 약하고, 서식에 따라 표 머리글 일부를 놓칩니다.
- 진동은 안드로이드 크롬에서만 나고, 세기·방향을 조절할 수 없습니다(웹 Vibration API). 방향은 음성으로 대신합니다.
- 받아쓰기는 획 순서와 방향을 판정하지 않습니다.
- 안드로이드 TalkBack을 켜면 화면을 만지는 동작을 TalkBack이 가져가 글씨를 쓸 수 없습니다. 쓰는 화면은 앱 자체 음성으로 씁니다.
- 출력 PDF는 사진 한 장을 한 쪽으로 쓰므로 원본 PDF를 다시 만드는 것은 아닙니다.

## 글꼴

Pretendard(화면), 도현체(Do Hyeon, 받아쓰기 보조선), 주아체(Jua)를 SIL Open Font License로 포함합니다. 라이선스 원문은 `app/assets/fonts/`에 있습니다.

# undersign-assist

시각장애인이 **종이 문서**를 혼자 읽고, 쓰고, 서명하고, 판단할 수 있게 돕는 앱이다.
한국코드페어 해커톤 출품작이며 여러 팀원이 함께 관리한다.

## 가장 중요한 전제: 종이 문서

- 입력은 언제나 **실물 종이 문서의 사진**이다. 카메라로 찍거나, 이미 찍어 둔 사진을 폴더에서 불러온다. PDF, HWP 같은 디지털 파일은 1차 입력이 아니다.
- 대상 문서: 근로계약서 등 계약서, 가정통신문, 개인정보 동의서.
- 쓰기와 서명도 **종이 위에 펜으로** 한다. 앱은 다시 찍은 사진으로 확인만 한다.
- 사용자는 화면을 볼 수 없다고 가정한다. 모든 결과는 음성으로 전달되어야 하고, 화면 표시는 보조다.

## 완전 소프트웨어

- 아두이노 등 하드웨어를 쓰지 않는다. 이전 프로젝트의 BLE 진동은 **소리 신호와 음성**으로 대체한다.

## 화면 구조

화면은 하나다 (`app/lib/screens/workspace_screen.dart`).

- **왼쪽 큰 영역** (`widgets/document_stage.dart`): 앱을 켜자마자 카메라가 켜진다. 사진을 받으면 그 사진으로 바뀌고, 읽기가 끝나면 인식한 줄의 위치를 사진 위에 상자로 그린다(찾은 항목은 굵게).
- **오른쪽 패널**: 위에서부터 `찍기`(사진이 있으면 `다시 찍기`), `사진 불러오기`, 네 단계 목록, 고른 단계의 내용.
- 사진이 없으면 단계를 고를 수 없다. 사진을 받으면 **바로 읽기가 실행되고** 요약을 음성으로 들려준다. 화면을 보지 않는 사용자가 읽기 버튼을 따로 찾지 않아도 되게 하기 위해서다.
- 너비 900 미만이면 위아래로 쌓인다(카메라 위, 패널 아래).
- 키보드: `C` 찍기, `O` 사진 불러오기, `1`~`4` 단계 고르기, `Esc` 다시 찍기.

## 네 단계

순서는 실제 사용 순서인 **읽기 → 판단 → 쓰기 → 서명**이다. 판단 없이 서명하게 만드는 흐름은 앱의 취지에 어긋나므로 판단을 서명보다 앞에 둔다.

| 단계 | 상태 | Flutter | 백엔드 |
|---|---|---|---|
| 읽기 | 동작함: 글자와 위치 인식, 문서 종류 구분, 항목 추출, 요약·전체 듣기 | `app/lib/features/read/` | `backend/app/routers/read.py` |
| 판단 | 화면만 있음 (예시 카드) | `app/lib/features/judge/` | `backend/app/routers/judge.py` |
| 쓰기 | 동작함: 칸 고르기 → 종이에 쓰기 → 다시 찍어 그 칸에 쓰인 글자 읽어주기 | `app/lib/features/write/` | `backend/app/routers/write.py` |
| 서명 | 화면만 있음 (판단 다시 듣기 → 서명란 찾기 → 서명 전 확인) | `app/lib/features/sign/` | `backend/app/routers/sign.py` |

공유 상태는 `models/workspace_state.dart`(사진, 읽기 결과, 고른 단계)에 있다. 읽기 결과는 `models/recognized_document.dart`이며 백엔드 `app/models.py`와 모양이 같다.

## 읽기 동작 방식

1. **글자 인식** (`backend/app/services/ocr.py`): `OCR_PROVIDER`로 고른다.
   - `tesseract`(기본): 이 PC의 Tesseract 한국어 데이터. 키와 인터넷 없이 동작한다. `--psm 6`(문서를 한 덩어리로 보기)과 한국어 전용이 시험해 본 설정 중 가장 정확했다. 인쇄 글자는 잘 읽지만 손글씨는 약하다.
   - `google`: Google Cloud Vision. 손글씨에 더 정확하다. 서비스 계정 키 경로를 `backend/.env`의 `GOOGLE_APPLICATION_CREDENTIALS`에 직접 넣어야 한다. 이전 프로젝트 레포의 키는 거부된다(폐기된 것으로 보임).
2. **문서 종류** (`services/doc_reader.py`): `rules/doc_types.json`의 핵심어가 문서에 몇 번 나왔는지 세서 가장 많은 종류를 고른다. 2번 미만이면 "알 수 없는 문서". AI가 아니라 규칙이다.
3. **항목 추출**: 같은 규칙 파일에 문서 종류별 항목 이름(예: 임금 ← 시급, 시간급, 임금)이 있다. 그 이름이 있는 줄에서 뒤의 글자를, 없으면 다음 줄을 값으로 쓴다.
4. 문서 종류나 항목을 늘릴 때는 규칙 파일만 고친다.

## 판단의 원칙

- AI는 문서를 **읽는 일**만 한다. 계산과 판정은 규칙과 수식이 한다. AI가 숫자나 법 기준을 지어내면 안 된다.
- 법 기준 값(최저임금 등)은 공식 자료에서 확인해 데이터 파일로 분리한다. 기억에 의존해 코드에 숫자를 박지 않는다.
- 결과는 단정하지 않는다. "기준보다 낮아 보임, 확인 필요"처럼 말하고, 근거(문서 원문 문장과 비교 기준)를 함께 준다.
- 앱이 할 수 없는 일: 서류 위조 판별, 상대방 신원 확인, 실시간 권리관계 확인. 화면과 발표에서 한계로 밝힌다.
- 백엔드는 받은 사진을 메모리에서만 처리하고 디스크에 남기지 않는다.

## 구조

```
app/                    Flutter 앱 (웹으로 실행)
  lib/main.dart         시작점. 웹 스크린리더용 의미 정보를 켠다
  lib/screens/          한 화면 (workspace_screen)
  lib/features/<단계>/  단계별 패널. 단계 하나에 폴더 하나
  lib/models/           사진, 읽기 결과, 화면 공유 상태
  lib/services/         백엔드 호출, 카메라, 음성 안내
  lib/widgets/          카메라·사진 영역, 패널 공통 틀
  lib/theme/            색과 글꼴 (임시)
  assets/fonts/         도현체, 주아체 (OFL, 오프라인 동작용으로 포함)
backend/                FastAPI 서버
  app/main.py           앱 생성, CORS, 라우터 등록
  app/models.py         단계들이 공유하는 데이터 모양 (Flutter의 models와 맞춘다)
  app/routers/          단계별 API. 단계 하나에 파일 하나
  app/services/         글자 인식(ocr), 문서 종류·항목(doc_reader)
  app/rules/            문서 종류별 핵심어와 항목 규칙 (JSON)
samples/                시험·시연용 가짜 문서 사진
```

## 디자인 (나중에 정한다)

- 지금은 화면 구조만 잡은 임시 흰 바탕 테마다. 색과 글꼴은 `app/lib/theme/app_theme.dart` 한 곳에서만 정의하고 화면에서 직접 색을 쓰지 않는다.
- 방향: 흰 바탕에 아주 옅은 유색 그라데이션. 게임처럼 보이지 않게 한다. 어두운 바탕은 쓰지 않기로 했다.
- 글꼴: 제목은 **도현체**(`AppFonts.display`), 본문은 **주아체**(`AppFonts.body`).
- 저시력 사용자를 위해 버튼(높이 64 이상)과 글씨는 크게, 글자 대비는 높게 한다.
- 단계 패널은 `PanelSection`으로 같은 틀(제목, 설명, 내용)을 쓴다. 기능이 아직 없는 단계는 `preparing: true`로 "준비 중" 표시를 단다.

## 샘플 문서

`samples/`에 시험과 시연용으로 만든 가짜 문서가 있다 (계약서, 빈칸을 채운 계약서, 가정통신문, 개인정보 동의서). 실제 개인정보는 넣지 않는다.

## 실행

백엔드:

```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

앱 (다른 터미널):

```
cd app
flutter pub get
flutter run -d chrome
```

- 백엔드 주소를 바꾸려면 `flutter run -d chrome --dart-define=API_BASE=http://주소:포트`.
- Windows 데스크톱 빌드는 이 PC에서 개발자 모드가 꺼져 있어 플러그인 링크를 만들 수 없다. 그래서 웹만 대상으로 한다.
- 카메라는 `localhost`나 HTTPS에서만 열린다.
- Tesseract가 기본 경로(`C:\Program Files\Tesseract-OCR`)에 없으면 `backend/.env`의 `TESSERACT_CMD`를 고친다. 한국어 데이터(`kor.traineddata`)가 있어야 한다.
- Windows에서 `uvicorn --reload`가 코드 변경을 반영하지 못한 적이 있다. 결과가 그대로면 서버를 껐다 켠다.

## 협업 규칙

- 단계 담당자는 자기 폴더(`app/lib/features/<단계>/`, `backend/app/routers/<단계>.py`)만 고친다. `models`, `services`, `widgets`, `theme`, `backend/app/models.py`를 바꿀 때는 팀에 먼저 알린다.
- 데이터 모양을 바꾸면 Flutter `models/recognized_document.dart`와 백엔드 `app/models.py`를 함께 고친다.
- **API 키, 서비스 계정 JSON, `.env`는 절대 커밋하지 않는다.** 이전 프로젝트에서 키가 커밋된 적이 있다. `backend/.env.example`에 이름만 적는다.
- 접근성: 모든 버튼에 스크린리더용 이름이 있어야 하고, 새 결과는 `Speech.announce`로 음성과 스크린리더 알림을 함께 보낸다.

## 참고 자료 (로컬, 커밋하지 않음)

- 이전 프로젝트(시각장애인 한글 손글씨 연습 앱): `C:\Users\User\.gemini\antigravity\scratch\rne_app-2-`
  - `rne_python/api_server.py`: Google Vision OCR, GPT, TTS 파이프라인
  - `rne_flutter/lib/widgets/drawingCanvas_widget.dart`의 `computePathInclusionRatio`: 획이 목표 경로 안에 들어간 비율로 정답을 판정하는 알고리즘
- 종이 서식 손글씨 데이터 180장(이미지 + 글자 위치·정답 라벨): `C:\Users\User\Downloads\rne\New_Sample (1)`. OCR 정확도 측정용. 출처와 이용 조건 확인 후 사용하고 출처를 표기한다.

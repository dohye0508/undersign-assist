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

## 화면 흐름

1. **첫 화면** (`screens/home_screen.dart`): 버튼 두 개만 있다. "카메라로 찍기", "사진 불러오기". 처음부터 기능 탭을 다 보여주지 않는다.
2. **카메라 화면** (`screens/camera_screen.dart`): 찍은 사진을 첫 화면으로 돌려준다.
3. **문서 화면** (`screens/document_screen.dart`): 사진을 받은 뒤에만 열린다. 네 단계 탭이 **읽기 → 판단 → 쓰기 → 서명** 순서로 있다. 판단 없이 서명하게 만드는 흐름은 앱의 취지에 어긋나므로 판단을 서명보다 앞에 둔다.

## 네 단계

| 단계 | 하는 일 | Flutter | 백엔드 |
|---|---|---|---|
| 읽기 | 글자와 위치를 인식하고, 문서 종류를 구분하고, 핵심 항목을 음성으로 읽어준다 | `app/lib/features/read/` | `backend/app/routers/read.py` |
| 판단 | 문서 종류별 규칙으로 빠진 항목과 불리한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다 | `app/lib/features/judge/` | `backend/app/routers/judge.py` |
| 쓰기 | 써야 할 칸을 안내하고, 종이에 쓴 글씨를 다시 찍어 무엇을 썼는지 읽어서 확인해 준다 | `app/lib/features/write/` | `backend/app/routers/write.py` |
| 서명 | 서명란 위치를 안내하고, 서명 전에 동의 여부를 마지막으로 확인한다 | `app/lib/features/sign/` | `backend/app/routers/sign.py` |

네 단계는 `DocumentSession`(사진 + 읽기 결과)을 함께 본다. 읽기가 결과를 채우면 나머지가 이어받는다.

## 판단의 원칙

- AI는 문서를 **읽는 일**만 한다. 계산과 판정은 규칙과 수식이 한다. AI가 숫자나 법 기준을 지어내면 안 된다.
- 법 기준 값(최저임금 등)은 공식 자료에서 확인해 데이터 파일로 분리한다. 기억에 의존해 코드에 숫자를 박지 않는다.
- 결과는 단정하지 않는다. "기준보다 낮아 보임, 확인 필요"처럼 말하고, 근거(문서 원문 문장과 비교 기준)를 함께 준다.
- 앱이 할 수 없는 일: 서류 위조 판별, 상대방 신원 확인, 실시간 권리관계 확인. 화면과 발표에서 한계로 밝힌다.
- 첫 화면에 "사진은 서버에 저장하지 않아요"라고 적혀 있다. 백엔드는 받은 사진을 처리한 뒤 디스크에 남기지 않는다.

## 구조

```
app/                    Flutter 앱 (웹으로 실행)
  lib/main.dart         시작점. 웹 스크린리더용 의미 정보를 켠다
  lib/theme/            색과 글꼴 (raibitScoreboard 디자인을 따른다)
  lib/screens/          첫 화면, 카메라, 문서 화면
  lib/features/<단계>/  단계별 화면. 단계 하나에 폴더 하나
  lib/models/           사진, 읽기 결과, 문서 세션
  lib/services/         백엔드 호출(api_client), 음성 안내(speech)
  lib/widgets/          큰 버튼, 단계 공통 틀(step_view)
  assets/fonts/         도현체, 주아체 (OFL, 오프라인 동작용으로 포함)
backend/                FastAPI 서버
  app/main.py           앱 생성, CORS, 라우터 등록
  app/models.py         단계들이 공유하는 데이터 모양 (Flutter의 models와 맞춘다)
  app/routers/          단계별 API. 단계 하나에 파일 하나
```

## 디자인

- `C:\Users\User\Downloads\raibitScoreboard`의 디자인을 따른다: 어두운 바탕(`#140A09`), 패널(`#1C0F0D`), 호박색 강조(`#FFB21E`)와 테두리, 둥근 모서리.
- 글꼴: 제목과 버튼은 **도현체**(`AppFonts.display`), 본문은 **주아체**(`AppFonts.body`). 색과 글꼴은 `app/lib/theme/app_theme.dart`에서만 정의하고 화면에서 직접 색을 쓰지 않는다.
- 저시력 사용자를 위해 버튼은 크게(높이 96), 글씨는 크게, 대비는 높게 한다.
- 네 단계 화면은 `StepView`로 같은 모양(제목, 설명, 큰 버튼 하나, 결과 칸)을 유지한다. 화면을 외워서 쓰는 사용자가 헷갈리지 않게 하기 위해서다.

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

백엔드 주소를 바꾸려면 `flutter run -d chrome --dart-define=API_BASE=http://주소:포트`.

- Windows 데스크톱 빌드는 이 PC에서 개발자 모드가 꺼져 있어 플러그인 링크를 만들 수 없다. 그래서 웹만 대상으로 한다.
- 카메라는 `localhost`나 HTTPS에서만 열린다.

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

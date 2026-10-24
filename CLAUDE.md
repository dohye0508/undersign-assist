# undersign-assist

시각장애인이 **종이 문서**를 혼자 읽고, 쓰고, 서명하고, 판단할 수 있게 돕는 웹앱이다.
한국코드페어 해커톤 출품작이며 여러 팀원이 함께 관리한다.

## 가장 중요한 전제: 종이 문서

- 입력은 언제나 **실물 종이 문서를 카메라로 찍은 사진**이다. PDF, HWP 같은 디지털 파일은 1차 입력이 아니다.
- 대상 문서: 근로계약서 등 계약서, 가정통신문, 개인정보 동의서.
- 쓰기와 서명도 **종이 위에 펜으로** 한다. 앱은 카메라로 다시 찍어 확인만 한다. 화면에 손가락으로 쓰는 기능은 연습용 보조일 뿐이다.
- 사용자는 화면을 볼 수 없다고 가정한다. 모든 결과는 음성으로 전달되어야 하고, 화면 표시는 보조다.

## 완전 소프트웨어

- 아두이노 등 하드웨어를 쓰지 않는다. 이전 프로젝트의 BLE 진동은 **소리 신호와 음성**으로 대체한다.
- 휴대폰에서는 `navigator.vibrate`를 보조로 쓸 수 있지만, 진동이 없어도 모든 기능이 동작해야 한다.

## 네 개의 탭

| 탭 | 하는 일 | 프론트엔드 | 백엔드 |
|---|---|---|---|
| 읽기 | 종이 문서를 찍어 글자와 위치를 인식하고, 문서 종류를 구분하고, 핵심 항목을 음성으로 읽어준다 | `frontend/js/tabs/read.js` | `backend/app/routers/read.py` |
| 쓰기 | 써야 할 칸을 안내하고, 종이에 쓴 글씨를 찍어 무엇을 썼는지 읽어서 확인해 준다 | `frontend/js/tabs/write.js` | `backend/app/routers/write.py` |
| 서명 | 서명란 위치를 안내하고, 서명 전에 동의 여부를 마지막으로 확인한다 | `frontend/js/tabs/sign.js` | `backend/app/routers/sign.py` |
| 판단 | 문서 종류별 규칙으로 빠진 항목과 불리한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다 | `frontend/js/tabs/judge.js` | `backend/app/routers/judge.py` |

실제 사용 흐름은 **읽기 → 판단 → 쓰기 → 서명**이다. 판단 없이 서명하게 만드는 흐름은 앱의 취지에 어긋난다.

## 판단의 원칙

- AI는 문서를 **읽는 일**만 한다. 계산과 판정은 규칙과 수식이 한다. AI가 숫자나 법 기준을 지어내면 안 된다.
- 법 기준 값(최저임금 등)은 공식 자료에서 확인해 데이터 파일로 분리한다. 기억에 의존해 코드에 숫자를 박지 않는다.
- 결과는 단정하지 않는다. "기준보다 낮아 보임, 확인 필요"처럼 말하고, 근거(문서 원문 문장과 비교 기준)를 함께 준다.
- 앱이 할 수 없는 일: 서류 위조 판별, 상대방 신원 확인, 실시간 권리관계 확인. 화면과 발표에서 한계로 밝힌다.

## 구조

```
backend/            FastAPI 서버. 프론트엔드 정적 파일도 함께 서빙한다
  app/main.py       앱 생성, 라우터 등록, 정적 파일 마운트
  app/models.py     탭들이 공유하는 데이터 모양 (인식된 문서, 글자 박스)
  app/routers/      탭별 API. 탭 하나에 파일 하나
frontend/           빌드 없는 HTML/CSS/JS (ES 모듈)
  js/main.js        탭 전환과 공통 초기화
  js/shared/        카메라, 음성, 소리 신호, API 호출 등 탭들이 함께 쓰는 모듈
  js/tabs/          탭별 화면 로직. 탭 하나에 파일 하나
```

## 실행

```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

브라우저에서 http://localhost:8000 을 연다. 카메라 권한은 `localhost`에서만 별도 HTTPS 없이 동작한다.

## 협업 규칙

- 탭 담당자는 자기 탭 파일(`js/tabs/<탭>.js`, `routers/<탭>.py`)만 고친다. `shared/`와 `models.py`를 바꿀 때는 팀에 먼저 알린다.
- 기능마다 브랜치를 만들고 PR로 합친다.
- **API 키, 서비스 계정 JSON, `.env`는 절대 커밋하지 않는다.** 이전 프로젝트에서 키가 커밋된 적이 있다. `.env.example`에 이름만 적는다.
- 접근성: 모든 버튼은 키보드로 조작 가능해야 하고, 새 결과는 `aria-live` 영역과 음성으로 함께 알린다.

## 참고 자료 (로컬, 커밋하지 않음)

- 이전 프로젝트(시각장애인 한글 손글씨 연습 앱): `C:\Users\User\.gemini\antigravity\scratch\rne_app-2-`
  - `rne_python/api_server.py`: Google Vision OCR, GPT, TTS 파이프라인
  - `rne_flutter/lib/widgets/drawingCanvas_widget.dart`의 `computePathInclusionRatio`: 획이 목표 경로 안에 들어간 비율로 정답을 판정하는 알고리즘. 서명 연습에 옮겨 쓸 수 있다
- 종이 서식 손글씨 데이터 180장(이미지 + 글자 위치·정답 라벨): `C:\Users\User\Downloads\rne\New_Sample (1)`. OCR 정확도 측정용. 출처와 이용 조건 확인 후 사용하고 출처를 표기한다.

# 들리는계약서 (undersign-assist)

시각장애인이 **종이 문서**를 혼자 읽고, 판단하고, 쓰고, 서명할 수 있게 돕는 앱입니다.

앱을 켜면 카메라가 바로 켜집니다. 계약서, 가정통신문, 개인정보 동의서 같은 종이 문서를 한 장씩 찍거나 사진으로 불러온 뒤 분석하면, 모든 페이지를 한 문서로 읽고 음성으로 안내합니다.

| 단계 | 하는 일 |
|---|---|
| 읽기 | 문서 종류를 알아내고 핵심 항목을 읽어줍니다. "요약 듣기", "전체 듣기"가 화면 맨 위에 있습니다 |
| 검토하세요! (판단) | 법령 데이터(근로기준법, 최저임금법, 주택임대차보호법, 개인정보 보호법 등)와 견주어 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려줍니다 |
| 쓰고 서명하기 | 써야 할 칸(성명, 날짜, 체크, 서명)을 음성으로 안내하고, 태블릿 패드에 쓰면 문서 사진의 그 자리에 들어갑니다 |
| 출력 | 글씨와 서명을 합성한 PDF를 내려받습니다 |

판정은 AI가 아니라 규칙과 수식이 합니다. AI는 문서를 읽는 일만 하고, 결과는 "~로 보여요, 확인이 필요해요"처럼 단정하지 않고 근거와 함께 들려줍니다. 법률 자문이 아닙니다.

## 실행

백엔드:

```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
# 글자 인식에 Tesseract(한국어 데이터 포함)가 필요합니다
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

앱:

```
cd app
flutter pub get
flutter run -d chrome
```

- 서버는 `127.0.0.1`에만 묶습니다 (`--host 0.0.0.0` 금지).
- 카메라는 `localhost`나 HTTPS에서만 열립니다.
- 선택 설정(AI 읽기의 `GROQ_API_KEY`, 손글씨용 Google Vision 등)은 `backend/.env`에 두며 `backend/.env.example`에 이름이 있습니다.

판단 엔진 시험:

```
python backend/tests/smoke_judge.py
```

## 함께 개발하기

구조, 원칙, 디자인, 협업 규칙, 남은 일은 모두 [CLAUDE.md](CLAUDE.md)에 있습니다. 비밀 값은 `backend/.env`에 두고 커밋하지 않습니다. 법령 데이터의 출처와 다시 만드는 법은 [backend/app/rules/laws/README.md](backend/app/rules/laws/README.md)에 있습니다.

## 글꼴

도현체(Do Hyeon)와 주아체(Jua)를 SIL Open Font License로 포함합니다. 라이선스 원문은 `app/assets/fonts/`에 있습니다.

# undersign-assist

시각장애인이 **종이 문서**를 혼자 읽고, 쓰고, 서명하고, 판단할 수 있게 돕는 웹앱입니다.

계약서, 가정통신문, 개인정보 동의서 같은 종이 문서를 카메라에 대면 음성으로 안내합니다.

| 탭 | 하는 일 |
|---|---|
| 읽기 | 문서를 찍어 종류를 알아내고 핵심 항목을 읽어줍니다 |
| 쓰기 | 써야 할 칸을 안내하고, 종이에 쓴 글씨를 다시 읽어 확인합니다 |
| 서명 | 서명란 위치를 안내하고, 서명 전에 마지막으로 확인합니다 |
| 판단 | 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려줍니다 |

## 실행

```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

브라우저에서 http://localhost:8000 을 엽니다.

## 함께 개발하기

구조, 원칙, 협업 규칙은 [CLAUDE.md](CLAUDE.md)에 있습니다. 비밀 값은 `backend/.env`에 두고 커밋하지 않습니다.

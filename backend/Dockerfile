# 들리는계약서 백엔드 컨테이너 (FastAPI + Tesseract 한국어).
# Hugging Face Spaces(Docker), Cloud Run, Render 같은 곳에 그대로 올린다.
# 비밀 값(GROQ_API_KEY)은 이미지에 넣지 않고 호스팅의 환경 변수/Secret으로 준다.
FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-kor \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# OMP_THREAD_LIMIT=1: Tesseract 스레드가 여럿이면 저사양 호스팅(Render 무료 0.1 CPU)에서 서로 싸워 한 장에 3분이 넘었다. 결과는 같다
ENV OCR_PROVIDER=tesseract \
    TESSERACT_CMD=tesseract \
    OMP_THREAD_LIMIT=1 \
    PORT=7860

# Hugging Face Spaces는 7860, Cloud Run은 PORT 환경 변수를 준다
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]

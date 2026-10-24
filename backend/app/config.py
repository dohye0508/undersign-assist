import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

OCR_PROVIDER = os.getenv("OCR_PROVIDER", "tesseract").lower()
TESSERACT_CMD = os.getenv("TESSERACT_CMD", r"C:\Program Files\Tesseract-OCR\tesseract.exe")

# Groq. 키가 없으면 AI 없이 규칙만으로 동작한다
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
# 항목 정리: 한국어 서식 문서에서 시험한 모델 중 가장 정확했다
GROQ_TEXT_MODEL = os.getenv("GROQ_TEXT_MODEL", "openai/gpt-oss-120b")
# 손글씨 읽기: 이미지를 받는 모델. 무료 한도가 작아(분당 출력 1,000토큰) 짧은 답에만 쓴다
GROQ_VISION_MODEL = os.getenv("GROQ_VISION_MODEL", "qwen/qwen3.8-27b")

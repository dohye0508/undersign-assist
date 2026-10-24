from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.routers import judge, read, sign, write

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"

app = FastAPI(title="undersign-assist")

app.include_router(read.router)
app.include_router(write.router)
app.include_router(sign.router)
app.include_router(judge.router)


@app.get("/api/health")
async def health() -> dict:
    return {"ok": True}


# API 라우터를 먼저 등록하고, 나머지 경로는 프론트엔드 정적 파일로 보낸다.
app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")

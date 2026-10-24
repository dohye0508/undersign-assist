from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import judge, read, sign, write

app = FastAPI(title="undersign-assist")

# Flutter 웹 개발 서버는 실행할 때마다 포트가 달라서 개발 중에는 모든 출처를 허용한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(read.router)
app.include_router(write.router)
app.include_router(sign.router)
app.include_router(judge.router)


@app.get("/api/health")
async def health() -> dict:
    return {"ok": True}

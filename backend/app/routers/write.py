"""쓰기: 써야 할 칸 안내 → 종이에 쓴 글씨를 찍어 무엇을 썼는지 읽어서 확인."""

from fastapi import APIRouter, File, Form, UploadFile
from pydantic import BaseModel

router = APIRouter(prefix="/api/write", tags=["쓰기"])


class WriteCheck(BaseModel):
    field: str  # 확인한 칸 (예: 성명, 주소)
    written: str  # 인식한 손글씨
    speech: str


@router.post("/check", response_model=WriteCheck)
async def check_writing(field: str = Form(...), photo: UploadFile = File(...)) -> WriteCheck:
    # TODO: 해당 칸 영역만 잘라 손글씨 인식
    # TODO: "'김민수'라고 쓰셨어요. 맞나요?" 형태로 되묻기
    await photo.read()
    return WriteCheck(field=field, written="", speech=f"{field} 칸 확인 기능은 아직 준비 중이에요.")

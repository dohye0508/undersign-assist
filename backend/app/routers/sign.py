"""서명: 서명란 위치 안내 → 서명 전 동의 여부 마지막 확인."""

from fastapi import APIRouter, File, UploadFile
from pydantic import BaseModel

from app.models import Box

router = APIRouter(prefix="/api/sign", tags=["서명"])


class SignatureSpot(BaseModel):
    found: bool
    box: Box | None = None
    speech: str


@router.post("/locate", response_model=SignatureSpot)
async def locate_signature(photo: UploadFile = File(...)) -> SignatureSpot:
    # TODO: "서명", "(인)", "성명" 글자 위치로 서명란 찾기
    # TODO: 펜 위치 기준 방향 안내 ("조금 더 오른쪽 아래예요")
    await photo.read()
    return SignatureSpot(found=False, speech="서명란 찾기 기능은 아직 준비 중이에요.")

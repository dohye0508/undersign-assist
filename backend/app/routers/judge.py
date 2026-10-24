"""판단: 문서 종류별 규칙으로 빠진 항목과 불리한 내용을 근거와 함께 알려준다.

AI는 읽기만 하고, 판정은 규칙과 수식이 한다. 최종 판단은 사용자가 한다.
"""

from enum import Enum

from fastapi import APIRouter
from pydantic import BaseModel

from app.models import RecognizedDocument

router = APIRouter(prefix="/api/judge", tags=["판단"])


class Level(str, Enum):
    OK = "ok"
    MISSING = "missing"  # 있어야 할 항목이 없음
    CAUTION = "caution"  # 기준보다 불리해 보임, 확인 필요


class Finding(BaseModel):
    level: Level
    item: str
    reason: str  # 비교한 기준
    evidence: str = ""  # 문서 원문 문장


class Judgement(BaseModel):
    findings: list[Finding] = []
    speech: str


@router.post("", response_model=Judgement)
async def judge_document(document: RecognizedDocument) -> Judgement:
    # TODO: 문서 종류별 규칙 파일 (backend/app/rules/<종류>.json) 불러오기
    # TODO: 필수 항목 체크리스트 + 기준 비교 계산
    return Judgement(speech="판단 기능은 아직 준비 중이에요.")

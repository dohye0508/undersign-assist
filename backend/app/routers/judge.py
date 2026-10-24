"""판단: 문서 종류별 규칙으로 빠진 항목과 불리한 내용을 근거와 함께 알려준다.

AI는 읽기만 하고, 판정은 규칙과 수식이 한다(backend/app/services/judge/). 최종 판단은 사용자가 한다.
"""

from __future__ import annotations

from enum import Enum

from fastapi import APIRouter
from pydantic import BaseModel

from app.models import RecognizedDocument
from app.services.judge import run as run_judge

router = APIRouter(prefix="/api/judge", tags=["판단"])


class Level(str, Enum):
    OK = "ok"
    MISSING = "missing"  # 있어야 할 항목이 없음
    CAUTION = "caution"  # 기준보다 불리해 보임, 확인 필요
    INFO = "info"  # 알아두면 좋은 권리 (경고 아님)


class LawRef(BaseModel):
    law_name: str = ""
    article_no: str = ""
    title: str = ""
    excerpt: str = ""  # 해당 항 원문 한 문단
    url: str = ""


class Finding(BaseModel):
    level: Level
    item: str
    reason: str = ""  # 비교한 기준
    evidence: str = ""  # 문서 원문 줄
    rule_id: str = ""
    severity: str = "info"  # critical / high / medium / info
    line: int = -1  # blocks 위치. 사진 위 상자 그리기용
    speech: str = ""  # 이 결과 하나를 읽어줄 문장
    basis: list[LawRef] = []


class Question(BaseModel):
    """문서만으로 알 수 없어 사용자에게 물을 것 (예: 사업장 인원)."""

    id: str
    text: str
    affects: list[str] = []
    affects_titles: list[str] = []  # affects 규칙의 이름 (예: "근로시간 한도 초과")
    options: dict[str, str] = {}  # yes/no/unknown -> 화면에 보일 말


class Judgement(BaseModel):
    findings: list[Finding] = []
    speech: str
    subtype: str = ""  # labor_part_time 등
    counts: dict[str, int] = {}
    questions: list[Question] = []
    disclaimer: str = ""


class JudgeRequest(RecognizedDocument):
    answers: dict[str, str] = {}  # 질문에 답한 뒤 다시 판단할 때 씀


@router.post("", response_model=Judgement)
async def judge_document(request: JudgeRequest) -> Judgement:
    result = run_judge(request, request.answers)
    return Judgement(**result)

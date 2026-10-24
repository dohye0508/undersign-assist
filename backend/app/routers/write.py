"""쓰기: 종이에 펜으로 쓴 뒤 다시 찍은 사진에서, 고른 칸에 무엇이 쓰였는지 읽어서 되묻는다."""

import asyncio
import re

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from app.models import Box, TextBlock
from app.services import ocr
from app.services.doc_reader import value_after

router = APIRouter(prefix="/api/write", tags=["쓰기"])


class WriteCheck(BaseModel):
    field: str  # 확인한 칸 (예: 성명)
    found: bool  # 사진에서 그 칸 이름을 찾았는지
    written: str  # 칸에 쓰여 있는 글자
    box: Box | None = None  # 칸 이름의 위치
    speech: str


@router.post("/check", response_model=WriteCheck)
async def check_writing(field: str = Form(...), photo: UploadFile = File(...)) -> WriteCheck:
    image = await photo.read()
    try:
        result = await asyncio.to_thread(ocr.recognize, image)
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"글자 인식 실패: {error}") from error

    label_line = next((line for line in result.lines if value_after(line.text, field) is not None), None)
    if label_line is None:
        return WriteCheck(
            field=field,
            found=False,
            written="",
            speech=f"{field} 칸을 찾지 못했어요. 그 칸이 화면에 들어오게 다시 찍어 주세요.",
        )

    written = _clean(value_after(label_line.text, field) or _text_to_the_right(label_line, result.lines))
    if not written:
        speech = f"{field} 칸이 비어 있는 것 같아요."
    else:
        speech = f"{field} 칸에 {written}, 라고 쓰여 있어요. 맞으면 다음 칸으로 넘어가세요."
    return WriteCheck(field=field, found=True, written=written, box=label_line.box, speech=speech)


# 서식에 미리 인쇄된 자리 표시. 이것만 있으면 아직 안 쓴 칸이다
PLACEHOLDER = re.compile(r"\(\s*(서\s*명|인|서\s*명\s*또\s*는\s*인)\s*\)?")
# 같은 줄의 다음 칸 이름 (예: "성명:")
NEXT_LABEL = re.compile(r"\s\S{1,6}\s*[:：]")


def _clean(text: str) -> str:
    text = NEXT_LABEL.split(" " + text, maxsplit=1)[0]
    return PLACEHOLDER.sub("", text).strip(" :：.,")


def _text_to_the_right(label: TextBlock, lines: list[TextBlock]) -> str:
    """칸 이름과 같은 높이에서 오른쪽에 따로 인식된 글자(표 칸, 손글씨)를 모은다."""
    top, bottom = label.box.y, label.box.y + label.box.height
    right_edge = label.box.x + label.box.width
    same_row = [
        line
        for line in lines
        if line is not label
        and line.box.x >= right_edge
        and min(bottom, line.box.y + line.box.height) - max(top, line.box.y) > label.box.height * 0.4
    ]
    same_row.sort(key=lambda line: line.box.x)
    return " ".join(line.text for line in same_row)

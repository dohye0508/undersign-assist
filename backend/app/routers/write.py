"""쓰기: 종이에 펜으로 쓴 뒤 다시 찍은 사진에서, 고른 칸에 무엇이 쓰였는지 읽어서 되묻는다."""

import asyncio
import re

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from app.models import Box, TextBlock
from app.services import llm, ocr
from app.services.doc_reader import value_after

router = APIRouter(prefix="/api/write", tags=["쓰기"])

# AI가 칸 상태를 알려줄 때 쓰는 약속된 답
EMPTY = "없음"
NO_FIELD = "칸없음"


class WriteCheck(BaseModel):
    field: str  # 확인한 칸 (예: 성명)
    found: bool  # 사진에서 그 칸을 찾았는지
    written: str  # 칸에 쓰여 있는 글자
    box: Box | None = None  # 칸 이름의 위치 (인쇄된 글자를 찾았을 때만)
    reader: str = "rules"  # 손글씨를 읽은 방식: "ai"(Groq 비전 모델) 또는 "rules"(OCR 결과)
    speech: str


@router.post("/check", response_model=WriteCheck)
async def check_writing(field: str = Form(...), photo: UploadFile = File(...)) -> WriteCheck:
    image = await photo.read()
    try:
        result = await asyncio.to_thread(ocr.recognize, image)
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"글자 인식 실패: {error}") from error

    # 인쇄된 칸 이름은 OCR이 잘 찾는다. 위치를 알려주는 데 쓴다
    label_line = next((line for line in result.lines if value_after(line.text, field) is not None), None)
    box = label_line.box if label_line else None

    # 손글씨는 OCR이 약해서 AI가 사진을 직접 보고 읽는다. 쓸 수 없으면 OCR 결과로 대신한다
    found, written, reader = label_line is not None, "", "rules"
    if llm.available():
        try:
            answer = await asyncio.to_thread(_read_handwriting, image, field, box)
            found = answer != NO_FIELD or label_line is not None
            written = "" if answer in (EMPTY, NO_FIELD) else answer
            reader = "ai"
        except llm.LlmError:
            pass
    if reader == "rules" and label_line is not None:
        written = _clean(value_after(label_line.text, field) or _text_to_the_right(label_line, result.lines))

    if not found:
        speech = f"{field} 칸을 찾지 못했어요. 그 칸이 화면에 들어오게 다시 찍어 주세요."
    elif not written:
        speech = f"{field} 칸이 비어 있는 것 같아요."
    else:
        speech = f"{field} 칸에 {written}, 라고 쓰여 있어요. 맞으면 다음 칸으로 넘어가세요."
    return WriteCheck(field=field, found=found, written=written, box=box, reader=reader, speech=speech)


def _read_handwriting(image: bytes, field: str, around: Box | None) -> str:
    prompt = (
        f"이 사진은 종이 서식이다. 인쇄된 '{field}' 글자 옆이나 아래의 빈칸에 사람이 손으로 쓴 글자를 찾아라.\n"
        "- 손으로 쓴 글자만 보이는 그대로 옮겨 적는다. 인쇄된 글자와 '(서명)', '(인)' 같은 자리 표시는 빼고 고치지 않는다.\n"
        f"- 칸은 있는데 손으로 쓴 글자가 없으면 '{EMPTY}'만 답한다.\n"
        f"- 사진에 '{field}' 칸이 없으면 '{NO_FIELD}'만 답한다.\n"
        "- 다른 설명은 하지 않는다."
    )
    # 칸 이름 위치를 알면 그 줄만 잘라 보낸다
    answer = llm.ask_about_image(prompt, ocr.to_jpeg(image, around=around))
    return answer.strip().strip("'\"“”‘’ .")


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

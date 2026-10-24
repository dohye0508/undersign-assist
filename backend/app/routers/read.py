"""읽기: 종이 문서 사진(여러 페이지) → 글자와 위치 인식 → 문서 종류 구분 → 핵심 항목 음성 안내.

여러 장을 한 문서로 읽는다. 페이지마다 글자를 인식한 뒤 줄을 차례로 이어 붙이고(각 줄에 페이지 번호),
문서 종류와 항목은 전체 글자로 한 번에 정한다. 계약서 둘째 장만으로는 종류를 알기 어렵기 때문이다.
"""

import asyncio

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.models import PageInfo, RecognizedDocument
from app.services import doc_reader, ocr

router = APIRouter(prefix="/api/read", tags=["읽기"])


@router.post("", response_model=RecognizedDocument)
async def read_document(photo: list[UploadFile] = File(...)) -> RecognizedDocument:
    """`photo` 필드를 페이지 순서대로 여러 번 보낸다. 한 장만 보내도 된다."""
    lines, pages = [], []
    for index, upload in enumerate(photo):
        image = await upload.read()
        try:
            result = await asyncio.to_thread(ocr.recognize, image)
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"{index + 1}페이지 글자 인식 실패: {error}") from error
        lines += [line.model_copy(update={"page": index}) for line in result.lines]
        pages.append(PageInfo(width=result.width, height=result.height))

    # AI 호출도 네트워크를 기다리므로 별도 스레드에서
    doc_type, scores, fields, reader = await asyncio.to_thread(doc_reader.read, lines)
    return RecognizedDocument(
        doc_type=doc_type,
        doc_type_label=doc_reader.label_of(doc_type),
        type_scores=scores,
        blocks=lines,
        fields=fields,
        full_text="\n".join(line.text for line in lines),
        image_width=pages[0].width,
        image_height=pages[0].height,
        pages=pages,
        reader=reader,
        speech=doc_reader.build_speech(doc_type, fields, lines),
    )

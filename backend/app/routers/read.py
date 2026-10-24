"""읽기: 종이 문서 사진 → 글자와 위치 인식 → 문서 종류 구분 → 핵심 항목 음성 안내."""

import asyncio

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.models import RecognizedDocument
from app.services import doc_reader, ocr

router = APIRouter(prefix="/api/read", tags=["읽기"])


@router.post("", response_model=RecognizedDocument)
async def read_document(photo: UploadFile = File(...)) -> RecognizedDocument:
    image = await photo.read()
    try:
        result = await asyncio.to_thread(ocr.recognize, image)
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"글자 인식 실패: {error}") from error

    # AI 호출도 네트워크를 기다리므로 별도 스레드에서
    doc_type, scores, fields, reader = await asyncio.to_thread(doc_reader.read, result.lines)
    return RecognizedDocument(
        doc_type=doc_type,
        doc_type_label=doc_reader.label_of(doc_type),
        type_scores=scores,
        blocks=result.lines,
        fields=fields,
        full_text=result.full_text,
        image_width=result.width,
        image_height=result.height,
        reader=reader,
        speech=doc_reader.build_speech(doc_type, fields, result.lines),
    )

"""읽기: 종이 문서 사진 → 글자와 위치 인식 → 문서 종류 구분 → 핵심 항목 음성 안내."""

from fastapi import APIRouter, File, UploadFile

from app.models import RecognizedDocument

router = APIRouter(prefix="/api/read", tags=["읽기"])


@router.post("", response_model=RecognizedDocument)
async def read_document(photo: UploadFile = File(...)) -> RecognizedDocument:
    # TODO: OCR로 글자와 위치(박스)를 모두 받는다 (이전 프로젝트는 위치를 버렸다)
    # TODO: 문서 종류 구분 (계약서 / 가정통신문 / 개인정보 동의서)
    # TODO: 종류별 핵심 항목 추출
    await photo.read()
    return RecognizedDocument(speech="읽기 기능은 아직 준비 중이에요. 사진은 잘 받았어요.")

"""단계들이 함께 쓰는 데이터 모양. Flutter `lib/models/recognized_document.dart`와 맞춘다.

모든 입력은 종이 문서를 찍은 사진이므로, 인식 결과는 글자와 그 위치(박스)를 함께 가진다.
쓰기 단계는 칸 위치를, 서명 단계는 서명란 위치를, 판단 단계는 항목 값을 이 결과에서 얻는다.
"""

from enum import Enum

from pydantic import BaseModel


class DocType(str, Enum):
    CONTRACT = "contract"  # 계약서 (근로계약서 등)
    NOTICE = "notice"  # 가정통신문
    CONSENT = "consent"  # 개인정보 동의서
    APPLICATION = "application"  # 신청서 (참가신청서 등)
    SUMMARY = "summary"  # 요약서·제출 서류 (작품 요약서 등)
    UNKNOWN = "unknown"


class Box(BaseModel):
    """사진 픽셀 좌표 (왼쪽 위가 0, 0)"""

    x: int
    y: int
    width: int
    height: int


class TextBlock(BaseModel):
    """한 줄의 글자와 그 위치"""

    text: str
    box: Box
    page: int = 0  # 몇 번째 사진(페이지)의 줄인지. 0부터. box는 그 페이지 사진의 좌표
    confidence: float | None = None  # OCR 엔진 신뢰도(0~100), 정확도 확률은 아님


class PageInfo(BaseModel):
    """페이지 사진의 크기 (방향을 바로잡은 뒤). 서명을 합성할 때 좌표 기준이 된다"""

    width: int
    height: int


class Field(BaseModel):
    label: str  # 항목 이름 (예: 임금)
    value: str  # 문서에 적힌 값
    line: int  # 몇 번째 줄에서 찾았는지 (blocks의 위치). 못 찾으면 -1


class RecognizedDocument(BaseModel):
    doc_type: DocType = DocType.UNKNOWN
    doc_type_label: str = "알 수 없는 문서"
    type_scores: dict[str, int] = {}  # 제목·서로 다른 본문 근거의 가중 점수 (확률·출현 횟수가 아님)
    blocks: list[TextBlock] = []
    fields: list[Field] = []
    full_text: str = ""
    image_width: int = 0  # 첫 페이지 크기 (이전 버전과 호환)
    image_height: int = 0
    pages: list[PageInfo] = []  # 페이지마다 사진 크기. 페이지 수는 len(pages)
    reader: str = "rules"  # 항목을 정리한 방식: "ai"(Groq) 또는 "rules"(규칙 파일)
    speech: str = ""  # 사용자에게 읽어줄 요약
    needs_review: bool = False
    review_pages: list[int] = []  # 다시 확인할 페이지, 0부터

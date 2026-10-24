"""탭들이 함께 쓰는 데이터 모양.

모든 입력은 종이 문서를 찍은 사진이므로, 인식 결과는 글자와 그 위치(박스)를 함께 가진다.
쓰기 탭은 칸 위치를, 서명 탭은 서명란 위치를, 판단 탭은 항목 값을 이 결과에서 얻는다.
"""

from enum import Enum

from pydantic import BaseModel


class DocType(str, Enum):
    CONTRACT = "contract"  # 계약서 (근로계약서 등)
    NOTICE = "notice"  # 가정통신문
    CONSENT = "consent"  # 개인정보 동의서
    UNKNOWN = "unknown"


class Box(BaseModel):
    x: int
    y: int
    width: int
    height: int


class TextBlock(BaseModel):
    text: str
    box: Box


class RecognizedDocument(BaseModel):
    doc_type: DocType = DocType.UNKNOWN
    blocks: list[TextBlock] = []
    fields: dict[str, str] = {}  # 문서 종류별로 뽑아낸 항목 (예: 시급, 마감일)
    speech: str = ""  # 사용자에게 읽어줄 문장

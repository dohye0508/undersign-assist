"""사진 → 줄 단위 글자와 위치.

두 가지 방식을 지원한다 (`OCR_PROVIDER`):
- tesseract: 이 PC에 설치된 Tesseract(한국어 데이터 포함). 인터넷과 키 없이 동작한다. 인쇄 글자에 맞다.
- google: Google Cloud Vision. 손글씨에 더 정확하지만 서비스 계정 키가 필요하다.
사진은 메모리에서만 다루고 디스크에 저장하지 않는다.
"""

import io
from dataclasses import dataclass
from statistics import median

from PIL import Image, ImageOps

from app import config
from app.models import Box, TextBlock


@dataclass
class OcrResult:
    lines: list[TextBlock]
    width: int
    height: int

    @property
    def full_text(self) -> str:
        return "\n".join(line.text for line in self.lines)


def recognize(image_bytes: bytes) -> OcrResult:
    image = _open(image_bytes)
    if config.OCR_PROVIDER == "google":
        lines = _google(image)
    else:
        lines = _tesseract(image)
    return OcrResult(lines=lines, width=image.width, height=image.height)


def _open(image_bytes: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(image_bytes))
    # 휴대폰 사진은 회전 정보가 따로 있어서, 실제 방향으로 돌려야 좌표가 맞는다
    return ImageOps.exif_transpose(image).convert("RGB")


def _union(boxes: list[tuple[int, int, int, int]]) -> Box:
    left = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    right = max(b[0] + b[2] for b in boxes)
    bottom = max(b[1] + b[3] for b in boxes)
    return Box(x=left, y=top, width=right - left, height=bottom - top)


def _tesseract(image: Image.Image) -> list[TextBlock]:
    import pytesseract

    pytesseract.pytesseract.tesseract_cmd = config.TESSERACT_CMD
    gray = image.convert("L")
    # 작은 사진은 키워야 한글 획이 뭉개지지 않는다
    if gray.width < 1600:
        scale = 1600 / gray.width
        gray = gray.resize((1600, round(gray.height * scale)), Image.LANCZOS)
    else:
        scale = 1.0
    # psm 6: 문서를 한 덩어리 글로 본다. 서식 문서에서 줄이 끊기지 않고 가장 정확했다
    # kor만 쓴다: eng를 섞으면 흐린 한글을 영어 글자로 잘못 읽는 일이 많았다
    data = pytesseract.image_to_data(
        gray, lang="kor", config="--psm 6", output_type=pytesseract.Output.DICT
    )

    # Tesseract는 단어를 (블록, 문단, 줄) 번호로 묶어 준다
    grouped: dict[tuple[int, int, int], list[tuple[str, tuple[int, int, int, int]]]] = {}
    for i, text in enumerate(data["text"]):
        text = text.strip()
        if not text or float(data["conf"][i]) < 0:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        box = tuple(round(data[k][i] / scale) for k in ("left", "top", "width", "height"))
        grouped.setdefault(key, []).append((text, box))

    lines = []
    for words in grouped.values():
        words.sort(key=lambda w: w[1][0])
        lines.append(TextBlock(text=_join_words(words), box=_union([b for _, b in words])))
    lines.sort(key=lambda line: (line.box.y, line.box.x))
    return lines


def _join_words(words: list[tuple[str, tuple[int, int, int, int]]]) -> str:
    """한국어 모델은 글자마다 띄어 쓰는 경우가 많아서, 실제 간격이 넓을 때만 띄운다."""
    gap_limit = median(b[3] for _, b in words) * 0.5
    text = words[0][0]
    for (_, prev), (word, box) in zip(words, words[1:]):
        gap = box[0] - (prev[0] + prev[2])
        text += (" " if gap > gap_limit else "") + word
    return text


def _google(image: Image.Image) -> list[TextBlock]:
    from google.cloud import vision

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=92)
    response = vision.ImageAnnotatorClient().document_text_detection(
        image=vision.Image(content=buffer.getvalue()),
        image_context={"language_hints": ["ko"]},
    )
    if response.error.message:
        raise RuntimeError(response.error.message)

    breaks = vision.TextAnnotation.DetectedBreak.BreakType
    lines = []
    for page in response.full_text_annotation.pages:
        for block in page.blocks:
            for paragraph in block.paragraphs:
                text = ""
                for word in paragraph.words:
                    for symbol in word.symbols:
                        text += symbol.text
                        kind = symbol.property.detected_break.type_
                        if kind in (breaks.SPACE, breaks.SURE_SPACE):
                            text += " "
                        elif kind in (breaks.EOL_SURE_SPACE, breaks.LINE_BREAK):
                            text += "\n"
                xs = [v.x for v in paragraph.bounding_box.vertices]
                ys = [v.y for v in paragraph.bounding_box.vertices]
                box = Box(x=min(xs), y=min(ys), width=max(xs) - min(xs), height=max(ys) - min(ys))
                for part in text.strip().split("\n"):
                    if part.strip():
                        lines.append(TextBlock(text=part.strip(), box=box))
    return lines

"""사진 → 줄 단위 글자와 위치.

두 가지 방식을 지원한다 (`OCR_PROVIDER`):
- tesseract: 이 PC에 설치된 Tesseract(한국어 데이터 포함). 인터넷과 키 없이 동작한다. 인쇄 글자에 맞다.
- google: Google Cloud Vision. 손글씨에 더 정확하지만 서비스 계정 키가 필요하다.
사진은 메모리에서만 다루고 디스크에 저장하지 않는다.
"""

import io
import re
from dataclasses import dataclass
from statistics import mean, median

from PIL import Image, ImageChops, ImageFilter, ImageOps

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


def to_jpeg(image_bytes: bytes, around: Box | None = None, max_side: int = 1024) -> bytes:
    """AI에 보낼 사진. 방향을 바로잡고 너무 크면 줄인다.

    around를 주면 그 상자가 있는 가로 띠만 잘라 보낸다. 사진이 작을수록 AI 요금 한도(입력 토큰)를 덜 쓴다.
    """
    image = _open(image_bytes)
    if around is not None:
        top = max(0, around.y - around.height * 2)
        bottom = min(image.height, around.y + around.height * 4)
        image = image.crop((0, top, image.width, bottom))
    image.thumbnail((max_side, max_side))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


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


# 두 번 읽기(아래 _merge_passes)에서 쓰는 기준. 값은 Tesseract 단어 신뢰도(0~100)의 줄 평균
WEAK_CONF = 70  # 이보다 낮은 psm 6 줄은 잘못 읽었을 가능성이 커서 바꿀 수 있다
STRONG_CONF = 75  # 이보다 높은 psm 11 줄만 가져온다
KEEP_LETTERS_RATIO = 0.6  # 바꿀 때 글자 수가 이 비율보다 줄어들면 바꾸지 않는다 ("예 □ 아니요 □" → "예 □" 방지)
_LETTER = re.compile(r"[가-힣0-9A-Za-z]")


@dataclass
class _Line:
    block: TextBlock
    conf: float  # 단어 신뢰도의 평균


def _tesseract(image: Image.Image) -> list[TextBlock]:
    import pytesseract

    pytesseract.pytesseract.tesseract_cmd = config.TESSERACT_CMD
    gray = _flatten_lighting(image.convert("L"))
    # 작은 사진은 키워야 한글 획이 뭉개지지 않는다
    if gray.width < 1600:
        scale = 1600 / gray.width
        gray = gray.resize((1600, round(gray.height * scale)), Image.LANCZOS)
    else:
        scale = 1.0
    # psm 6: 문서를 한 덩어리 글로 본다. 서식 문서에서 줄이 끊기지 않고 가장 정확했다.
    # 다만 표의 회색 머리글 칸("수집 목적 | 수집 항목 | 보유 기간")처럼 배경이 있는 칸은 통째로 놓치거나
    # 엉뚱한 글자("순 버 베 괴")로 읽는다. 그런 칸은 psm 11(흩어진 글자)이 잘 읽으므로 한 번 더 읽어서
    # 신뢰도 낮은 줄만 바꿔 넣는다. 신뢰도 높은 psm 6 줄은 건드리지 않아 깨끗한 문서의 결과는 그대로다.
    primary = _tesseract_lines(pytesseract, gray, 6, scale)
    orientation = 0
    # EXIF is handled by _open. Screenshots/scans can have no orientation tag.
    # Try bounded orthogonal rotations only when the normal pass is unreliable.
    initial_quality = _quality(primary)
    if initial_quality < 55 and _has_ink(gray):
        best_quality = initial_quality
        best_image = gray
        for angle, transpose in ((90, Image.Transpose.ROTATE_90),
                                 (180, Image.Transpose.ROTATE_180),
                                 (270, Image.Transpose.ROTATE_270)):
            candidate_image = gray.transpose(transpose)
            candidate = _tesseract_lines(pytesseract, candidate_image, 6, scale)
            quality = _quality(candidate)
            if quality >= 55 and quality >= initial_quality + 15 and quality > best_quality:
                primary, best_image, orientation, best_quality = candidate, candidate_image, angle, quality
        gray = best_image
    secondary = _tesseract_lines(pytesseract, gray, 11, scale)
    lines = [line.block for line in _merge_passes(primary, secondary)]
    # Sort in reading orientation, then map boxes back to the unchanged photo.
    lines.sort(key=lambda line: (line.box.y, line.box.x))
    if orientation:
        lines = [line.model_copy(update={"box": _original_box(line.box, orientation, image.width, image.height)})
                 for line in lines]
    return lines


def _flatten_lighting(gray: Image.Image) -> Image.Image:
    """Remove broad shadows without changing geometry or adding a dependency."""
    background = gray.resize((max(1, gray.width // 32), max(1, gray.height // 32)), Image.Resampling.BOX)
    background = background.filter(ImageFilter.GaussianBlur(3))
    histogram = background.histogram()
    total = sum(histogram)

    def percentile(fraction: float) -> int:
        count = 0
        for value, frequency in enumerate(histogram):
            count += frequency
            if count >= total * fraction:
                return value
        return 255

    if percentile(0.9) - percentile(0.1) < 35 and percentile(0.5) >= 210:
        return gray
    background = background.resize(gray.size, Image.Resampling.BILINEAR)
    corrected = ImageChops.subtract(gray, background, offset=255)
    # Do not discard the darkest percentile: a short heading/signature can
    # occupy less than 1% of a mostly blank form.
    return ImageOps.autocontrast(corrected, cutoff=(0, 1))


def _quality(lines: list[_Line]) -> float:
    counts = [_letters(line.block.text) for line in lines]
    total = sum(counts)
    if not total:
        return 0.0
    return sum(line.conf * count for line, count in zip(lines, counts)) / total * min(total / 40, 1)


def _has_ink(gray: Image.Image) -> bool:
    histogram = gray.histogram()
    return sum(histogram[:160]) > gray.width * gray.height * 0.001


def _original_box(box: Box, angle: int, width: int, height: int) -> Box:
    """Inverse of a lossless PIL transpose, in original photo pixel coordinates."""
    if angle == 90:
        x, y, w, h = width - box.y - box.height, box.x, box.height, box.width
    elif angle == 180:
        x, y, w, h = width - box.x - box.width, height - box.y - box.height, box.width, box.height
    else:  # 270
        x, y, w, h = box.y, height - box.x - box.width, box.height, box.width
    left, top = max(0, min(x, width - 1)), max(0, min(y, height - 1))
    right, bottom = max(left + 1, min(x + w, width)), max(top + 1, min(y + h, height))
    return Box(x=left, y=top, width=right - left, height=bottom - top)


def _tesseract_lines(pytesseract, gray: Image.Image, psm: int, scale: float) -> list[_Line]:
    # kor만 쓴다: eng를 섞으면 흐린 한글을 영어 글자로 잘못 읽는 일이 많았다
    data = pytesseract.image_to_data(
        gray, lang="kor", config=f"--psm {psm}", output_type=pytesseract.Output.DICT
    )

    # Tesseract는 단어를 (블록, 문단, 줄) 번호로 묶어 준다
    grouped: dict[tuple[int, int, int], list[tuple[str, tuple[int, int, int, int], float]]] = {}
    for i, text in enumerate(data["text"]):
        text = text.strip()
        conf = float(data["conf"][i])
        if not text or conf < 0:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        box = tuple(round(data[k][i] / scale) for k in ("left", "top", "width", "height"))
        grouped.setdefault(key, []).append((text, box, conf))

    lines = []
    for words in grouped.values():
        words.sort(key=lambda w: w[1][0])
        block = TextBlock(text=_join_words([(t, b) for t, b, _ in words]), box=_union([b for _, b, _ in words]))
        lines.append(_Line(block=block, conf=mean(c for _, _, c in words)))
    return lines


def _overlaps(a: Box, b: Box) -> bool:
    """같은 줄 자리인지: 가로로 겹치고, 세로로는 낮은 쪽 높이의 절반 이상 겹친다."""
    horizontal = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
    vertical = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
    return horizontal > 0 and vertical >= 0.5 * min(a.height, b.height)


def _letters(text: str) -> int:
    return len(_LETTER.findall(text))


def _merge_passes(primary: list[_Line], secondary: list[_Line]) -> list[_Line]:
    """psm 6 결과(primary)를 기본으로 두고, 신뢰도 낮은 줄만 psm 11 결과(secondary)의 신뢰도 높은 줄로 바꾼다.

    - 신뢰도 높은 primary 줄과 겹치는 secondary 줄은 쓰지 않는다 (같은 글자가 두 번 들어가면 쓰기 칸이 중복된다).
    - 아무 primary 줄과도 겹치지 않는 secondary 줄은 그대로 더한다 (psm 6이 통째로 놓친 칸).
    - 신뢰도 낮은 primary 줄은, 그 자리에 들어올 secondary 줄들의 글자 수가 충분할 때만 뺀다.
      글자가 크게 줄면(예: "예 □ 아니요 □" → "예 □") 원래 줄을 남긴다.
    """
    strong_primary = [line for line in primary if line.conf >= WEAK_CONF]
    candidates = [
        line
        for line in secondary
        if line.conf >= STRONG_CONF and not any(_overlaps(line.block.box, p.block.box) for p in strong_primary)
    ]

    accepted: list[_Line] = []
    kept: list[_Line] = list(strong_primary)
    for weak in primary:
        if weak.conf >= WEAK_CONF:
            continue
        group = [c for c in candidates if _overlaps(c.block.box, weak.block.box)]
        if group and sum(_letters(c.block.text) for c in group) >= KEEP_LETTERS_RATIO * _letters(weak.block.text):
            accepted += [c for c in group if c not in accepted]
        else:
            kept.append(weak)
    # 어느 primary 줄과도 안 겹치는 것은 빈 자리를 채운다
    for line in candidates:
        if line not in accepted and not any(_overlaps(line.block.box, p.block.box) for p in primary):
            accepted.append(line)
    return kept + accepted


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

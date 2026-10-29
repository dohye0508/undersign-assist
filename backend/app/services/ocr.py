"""사진 → 줄 단위 글자와 위치.

두 가지 방식을 지원한다 (`OCR_PROVIDER`):
- tesseract: 이 PC에 설치된 Tesseract(한국어 데이터 포함). 인터넷과 키 없이 동작한다. 인쇄 글자에 맞다.
- google: Google Cloud Vision. 손글씨에 더 정확하지만 서비스 계정 키가 필요하다.
사진은 메모리에서만 다루고 디스크에 저장하지 않는다.
"""

import io
import math
import re
from collections import Counter, deque
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
    needs_review: bool = False

    @property
    def full_text(self) -> str:
        return "\n".join(line.text for line in self.lines)


def recognize(image_bytes: bytes) -> OcrResult:
    image = _open(image_bytes)
    if config.OCR_PROVIDER == "google":
        lines = _google(image)
    else:
        working, offset = _page_crop(image, distant_only=True)
        lines = _tesseract(working)
        if _needs_review(lines) or _quality([_Line(b, b.confidence or 0) for b in lines]) < 70:
            for adaptive in (False, True):
                recovered = _layout_recovery(working, adaptive=adaptive)
                original = [_Line(b, b.confidence or 0) for b in lines]
                candidate = [_Line(b, b.confidence or 0) for b in recovered]
                candidate = _preserve_reliable_regions(candidate, original)
                recovered = [b.block for b in candidate]
                # Region segmentation must not silently turn an unreadable long
                # body into a confident heading. Keep most of the reliable text.
                accepted = _recovery_improves(candidate, original)
                if accepted:
                    lines = recovered
                if accepted and not _needs_review(lines):
                    break
        if offset != (0, 0):
            lines = [b.model_copy(update={"box": b.box.model_copy(update={"x": b.box.x + offset[0], "y": b.box.y + offset[1]})}) for b in lines]
    return OcrResult(lines=lines, width=image.width, height=image.height,
                     needs_review=_needs_review(lines, group_lines=config.OCR_PROVIDER != "google"))


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
    gray = _flatten_lighting(_clear_background(_light_background(image.convert("L"))))
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
    deskew_angle = 0.0
    oriented_size = gray.size
    if _quality(primary) < 95 and _has_ink(gray):
        gray, primary, deskew_angle = _deskew(gray, primary, pytesseract, scale)
    if _quality(primary) < 85:
        cleaned = _remove_rules(gray)
        if cleaned is not gray:
            candidate = _tesseract_lines(pytesseract, cleaned, 6, scale)
            if _improves(candidate, primary, 10):
                gray, primary = cleaned, candidate
    if _quality(primary) < 70 and _has_ink(gray):
        # Periodic screen scanlines split glyphs into stripes. A small median
        # reconnects strokes, then a threshold rejects the pale scanlines.
        cleaned = gray.filter(ImageFilter.MedianFilter(3)).point(lambda p: 0 if p < 145 else 255)
        candidate = _tesseract_lines(pytesseract, cleaned, 6, scale)
        if _improves(candidate, primary, 10):
            gray, primary = cleaned, candidate
    orientation = 0
    # EXIF is handled by _open. Screenshots/scans can have no orientation tag.
    # Try bounded orthogonal rotations only when the normal pass is unreliable.
    initial_quality = _quality(primary)
    before_orientation_angle, before_orientation_size = deskew_angle, gray.size
    if initial_quality < 70 and _has_ink(gray):
        best_quality = initial_quality
        best_image = gray
        for angle, transpose in ((90, Image.Transpose.ROTATE_90),
                                 (180, Image.Transpose.ROTATE_180),
                                 (270, Image.Transpose.ROTATE_270)):
            candidate_image = gray.transpose(transpose)
            candidate_size = candidate_image.size
            candidate = _tesseract_lines(pytesseract, candidate_image, 6, scale)
            quality = _quality(candidate)
            fine_angle = 0.0
            # A sideways AND tilted photo can fail every orthogonal pass. Fine
            # deskew belongs inside each plausible orientation hypothesis.
            if 25 <= quality < 85:
                candidate_image, candidate, fine_angle = _deskew(candidate_image, candidate, pytesseract, scale)
                quality = _quality(candidate)
            if quality >= 55 and quality >= initial_quality + 15 and quality > best_quality:
                primary, best_image, orientation, best_quality = candidate, candidate_image, angle, quality
                deskew_angle, oriented_size = fine_angle, candidate_size
        gray = best_image
    # Correct the small tilt left after orientation recovery. Projection uses
    # pixels, not document keywords; accept a retry only if OCR improves.
    if orientation and not deskew_angle:
        oriented_size = gray.size
        if _quality(primary) < 85:
            gray, primary, deskew_angle = _deskew(gray, primary, pytesseract, scale)
    secondary = _tesseract_lines(pytesseract, gray, 11, scale)
    lines = [line.block for line in _merge_passes(primary, secondary)]
    # Sort in reading orientation, then map boxes back to the unchanged photo.
    lines = _reading_order(lines)
    if deskew_angle:
        lines = [line.model_copy(update={"box": _unrotate_box(
            line.box, deskew_angle, tuple(v / scale for v in oriented_size), tuple(v / scale for v in gray.size)
        )}) for line in lines]
    if orientation:
        lines = [line.model_copy(update={"box": _original_box(line.box, orientation,
                 round(before_orientation_size[0]/scale), round(before_orientation_size[1]/scale))})
                 for line in lines]
        if before_orientation_angle:
            lines = [line.model_copy(update={"box": _unrotate_box(line.box, before_orientation_angle,
                     image.size, tuple(v/scale for v in before_orientation_size))}) for line in lines]
    return lines


def _deskew(gray, primary, pytesseract, scale):
    angle = _skew_angle(gray)
    if abs(angle) >= 1.5:
        candidate_image = gray.rotate(angle, Image.Resampling.BICUBIC, expand=True, fillcolor=255)
        candidate = _tesseract_lines(pytesseract, candidate_image, 6, scale)
        if _quality(candidate) >= max(55, _quality(primary) + 3):
            return candidate_image, candidate, angle
    return gray, primary, 0.0


def _improves(candidate: list[_Line], original: list[_Line], margin: float) -> bool:
    # Noise can increase mean confidence while destroying a previously legible
    # heading. Keep most of the reliably recognized characters on a retry.
    reliable_before = sum(_letters(b.block.text) for b in original if b.conf >= WEAK_CONF)
    reliable_after = sum(_letters(b.block.text) for b in candidate if b.conf >= WEAK_CONF)
    return _quality(candidate) >= _quality(original) + margin and reliable_after >= reliable_before * KEEP_LETTERS_RATIO


def _recovery_improves(candidate: list[_Line], original: list[_Line]) -> bool:
    if _improves(candidate, original, 5):
        return True
    # Whole-page scoring discounts fewer than 40 characters. A correctly read
    # blank form can therefore score below a long string of border/ruler noise.
    # Require several strong labels, not just a high-confidence heading.
    total = sum(_letters(b.block.text) for b in candidate)
    trusted = [b for b in candidate if b.conf >= STRONG_CONF]
    before = sum(_letters(b.block.text) for b in original if b.conf >= WEAK_CONF)
    after = sum(_letters(b.block.text) for b in trusted)
    confidence = sum(b.conf * _letters(b.block.text) for b in candidate) / max(1, total)
    return (12 <= total <= 60 and len(trusted) >= 4 and confidence >= 80
            and after >= before * KEEP_LETTERS_RATIO
            and _needs_review([b.block for b in original])
            and not _needs_review([b.block for b in candidate]))


def _preserve_reliable_regions(candidate: list[_Line], original: list[_Line]) -> list[_Line]:
    """Keep a good heading/label when region OCR weakens the same photo area."""
    kept = []
    for line in candidate:
        letters = _letters(line.block.text)
        matches = [old for old in original if old.conf >= WEAK_CONF
                   and _overlaps(line.block.box, old.block.box)
                   and letters * KEEP_LETTERS_RATIO <= _letters(old.block.text) <= max(letters*2, letters+8)]
        replacement = max(matches, key=lambda b: b.conf) if line.conf < WEAK_CONF and matches else line
        if replacement not in kept:
            kept.append(replacement)
    for line in original:
        if (line.conf >= STRONG_CONF and _letters(line.block.text) >= 2
                and not any(_overlaps(line.block.box, other.block.box) for other in kept)):
            kept.append(line)
    by_block = {id(line.block): line for line in kept}
    return [by_block[id(block)] for block in _reading_order([line.block for line in kept])]


def _light_background(gray: Image.Image) -> Image.Image:
    """Invert white text on a dark screen, without inverting shaded paper."""
    histogram = gray.histogram()
    peak = max(range(256), key=histogram.__getitem__)
    dark = sum(histogram[:max(0, peak - 35)])
    light = sum(histogram[min(256, peak + 35):])
    area = gray.width * gray.height
    if peak < 120 and max(dark * 2, area * 0.002) < light < area * 0.3:
        return ImageOps.invert(gray)
    return gray


def _clear_background(gray: Image.Image) -> Image.Image:
    """Whiten a dark desk connected to all four corners, preserving geometry."""
    sample = gray.copy()
    sample.thumbnail((240, 240), Image.Resampling.BOX)
    width, height = sample.size
    pixels = sample.tobytes()
    corners = (0, width - 1, width * (height - 1), len(pixels) - 1)
    if any(pixels[i] >= 150 for i in corners) or sum(p > 230 for p in pixels) < len(pixels) * 0.35:
        return gray
    mask = bytearray(len(pixels))
    queue = deque(corners)
    while queue:
        index = queue.popleft()
        if mask[index] or pixels[index] >= 150:
            continue
        mask[index] = 255
        x, y = index % width, index // width
        if x: queue.append(index - 1)
        if x + 1 < width: queue.append(index + 1)
        if y: queue.append(index - width)
        if y + 1 < height: queue.append(index + width)
    if sum(v == 255 for v in mask) < len(mask) * 0.05:
        return gray
    background = Image.frombytes("L", sample.size, bytes(mask)).filter(ImageFilter.MaxFilter(3)).resize(gray.size, Image.Resampling.NEAREST)
    return Image.composite(Image.new("L", gray.size, 255), gray, background)


def _remove_rules(gray: Image.Image) -> Image.Image:
    """Remove long horizontal/vertical rules, preserving short letter strokes."""
    ink = gray.point(lambda p: 255 if p < 180 else 0)

    def shifted(image, dx, dy):
        output = Image.new("L", image.size, 0)
        output.paste(image, (dx, dy))
        return output

    def opened(axis):
        # Power-of-two erosion/dilation implements a 128-pixel line kernel.
        result = ink
        for step in (1, 2, 4, 8, 16, 32, 64):
            result = ImageChops.darker(result, shifted(result, step if axis == 0 else 0, step if axis else 0))
        for step in (64, 32, 16, 8, 4, 2, 1):
            result = ImageChops.lighter(result, shifted(result, -step if axis == 0 else 0, -step if axis else 0))
        return result

    mask = ImageChops.lighter(opened(0), opened(1))
    pixels = mask.histogram()[255]
    if not 0.0005 < pixels / (gray.width * gray.height) < 0.25:
        return gray
    return Image.composite(Image.new("L", gray.size, 255), gray, mask)


def _skew_angle(gray: Image.Image) -> float:
    """Estimate bounded fine rotation from horizontal text projection peaks."""
    sample = gray.copy()
    sample.thumbnail((800, 1000), Image.Resampling.BOX)
    # Ignore photograph edges, which otherwise dominate short documents.
    inset_x, inset_y = round(sample.width * 0.03), round(sample.height * 0.03)
    sample = sample.crop((inset_x, inset_y, sample.width - inset_x, sample.height - inset_y))
    ink = sample.point(lambda p: 255 if p < 150 else 0)

    def score(angle):
        rotated = ink.rotate(angle, Image.Resampling.NEAREST, expand=True, fillcolor=0)
        rows = rotated.resize((1, rotated.height), Image.Resampling.BOX).tobytes()
        # Differences emphasize distinct text baselines over broad shadows.
        return sum((a - b) ** 2 for a, b in zip(rows, rows[1:]))

    scores = [(score(angle), angle) for angle in range(-18, 19)]
    best, angle = max(scores)
    if best < max(score(0) * 1.2, 100):
        return 0.0
    return max((score(angle + delta), angle + delta) for delta in (-0.5, 0, 0.5))[1]


def _unrotate_box(box: Box, angle: float, original_size, rotated_size) -> Box:
    """Inverse expanded Pillow rotation; enclose all four transformed corners."""
    width, height = original_size
    rw, rh = rotated_size
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    points = []
    for x in (box.x, box.x + box.width):
        for y in (box.y, box.y + box.height):
            dx, dy = x - rw / 2, y - rh / 2
            points.append((width / 2 + c * dx - s * dy, height / 2 + s * dx + c * dy))
    left = max(0, min(round(width) - 1, math.floor(min(p[0] for p in points))))
    top = max(0, min(round(height) - 1, math.floor(min(p[1] for p in points))))
    right = max(left + 1, min(round(width), math.ceil(max(p[0] for p in points))))
    bottom = max(top + 1, min(round(height), math.ceil(max(p[1] for p in points))))
    return Box(x=left, y=top, width=right - left, height=bottom - top)


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
        # PSM 6 sometimes joins two independent columns into one long line.
        # Short labels beside their values are kept together as a table row.
        splits = [i for i in range(1, len(words))
                  if words[i][1][0] - sum((words[i-1][1][0], words[i-1][1][2])) > 5 * median(w[1][3] for w in words)
                  and _letters("".join(w[0] for w in words[:i])) >= 4
                  and _letters("".join(w[0] for w in words[i:])) >= 4]
        starts = [0, *splits, len(words)]
        for start, end in zip(starts, starts[1:]):
            part = words[start:end]
            confidence = mean(c for _, _, c in part)
            block = TextBlock(text=_join_words([(t, b) for t, b, _ in part]), box=_union([b for _, b, _ in part]), confidence=confidence)
            lines.append(_Line(block=block, conf=confidence))
    return lines


def _reading_order(lines: list[TextBlock]) -> list[TextBlock]:
    """Read two sustained columns top-to-bottom, retaining spanning headers."""
    ordered = sorted(lines, key=lambda b: (b.box.y, b.box.x))
    gaps = []
    for i, first in enumerate(ordered):
        for second in ordered[i+1:]:
            if second.box.y > first.box.y + first.box.height:
                break
            left, right = sorted((first, second), key=lambda line: line.box.x)
            a, b = left.box, right.box
            if min(a.y+a.height, b.y+b.height) - max(a.y, b.y) < min(a.height, b.height) * 0.5:
                continue
            if b.x - a.x - a.width > 4 * min(a.height, b.height) and _letters(left.text) >= 6 and _letters(right.text) >= 4:
                gaps.append((a.x + a.width, b.x, min(a.y, b.y), max(a.y+a.height, b.y+b.height)))
    if len(gaps) < 3:
        return ordered
    cuts = [(sum(lo < (a+b)/2 < hi for lo, hi, _, _ in gaps), (a+b)/2) for a, b, _, _ in gaps]
    count, cut = max(cuts)
    if count < 3:
        return ordered
    matched = [g for g in gaps if g[0] < cut < g[1]]
    top = min(g[2] for g in matched)
    bottom = min((b.box.y for b in ordered if b.box.y >= top and b.box.x < cut < b.box.x + b.box.width), default=float("inf"))
    band = [b for b in ordered if top <= b.box.y < bottom]
    if any(b.box.x < cut < b.box.x + b.box.width for b in band):
        return ordered
    return ([b for b in ordered if b.box.y < top]
            + [b for b in band if b.box.x < cut]
            + [b for b in band if b.box.x >= cut]
            + [b for b in ordered if b.box.y >= bottom])


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
                        lines.append(TextBlock(text=part.strip(), box=box, confidence=paragraph.confidence * 100))
    return lines


def _needs_review(lines: list[TextBlock], group_lines=True) -> bool:
    """Flag weak/partial readings; OCR confidence is not a calibrated probability."""
    if not lines:
        return True
    measured = [b for b in lines if b.confidence is not None and _letters(b.text)]
    if not measured:  # Symbols alone are not text; legacy adapters have no score.
        return any(b.confidence is not None for b in lines)
    trusted = [b for b in measured if b.confidence >= 65]
    total = sum(_letters(b.text) for b in measured)
    reliable = sum(_letters(b.text) for b in trusted)
    quality = sum(b.confidence * _letters(b.text) for b in measured) / total
    bands = []
    # Boxes are in the original photo, which may be sideways. Group centers on
    # the short axis; enclosing boxes of tilted long lines overlap heavily.
    vertical = bool(trusted) and median(b.box.height / max(1, b.box.width) for b in trusted) > 2
    tolerance = max(6, median(min(b.box.height, b.box.width) for b in trusted) * 0.35) if trusted else 6
    for block in trusted:
        box = block.box
        center = box.x + box.width/2 if vertical else box.y + box.height/2
        if not any(abs(center - other) < tolerance for other in bands):
            bands.append(center)
    # The Google adapter currently repeats paragraph boxes for its text lines.
    row_count = len(bands) if group_lines else len(trusted)
    sparse_form = row_count >= 4 and reliable >= 12
    # A long, mostly garbled body must not pass on a legible heading. Keep the
    # sparse-form tolerance for short labels, but require stronger body quality.
    minimum_quality = 65 if total >= 120 else 60
    return quality < minimum_quality or reliable < total * 0.55 or (reliable < 24 and not sparse_form) or row_count < 2


def _page_crop(image: Image.Image, distant_only=False):
    """Bound a pale page on a dark desk; no perspective or size changes."""
    import cv2
    import numpy as np

    small = image.convert("L")
    small.thumbnail((600, 600))
    array = np.asarray(small)
    if max(array[0, 0], array[0, -1], array[-1, 0], array[-1, -1]) >= 160:
        return image, (0, 0)
    contours, _ = cv2.findContours((array > 190).astype("uint8") * 255, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return image, (0, 0)
    contour = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(contour)
    area = cv2.contourArea(contour)
    if area <= array.size * 0.07 or area <= w * h * 0.6 or (distant_only and w*h > array.size * 0.5):
        return image, (0, 0)
    # A bright half of a shaded sheet is not the whole page. Require the area
    # just outside its convex outline to look like the surrounding dark desk.
    hull = cv2.approxPolyDP(cv2.convexHull(contour), 3, True).reshape(-1, 2)
    center = hull.mean(axis=0)
    outside = []
    for start, end in zip(hull, np.roll(hull, -1, axis=0)):
        for fraction in (0.2, 0.4, 0.6, 0.8):
            point = start + (end-start)*fraction
            direction = point-center
            point += direction / max(1, np.linalg.norm(direction)) * 4
            px, py = np.rint(point).astype(int)
            if 0 <= px < small.width and 0 <= py < small.height:
                outside.append(array[py, px] < 160)
    if not outside or sum(outside) < len(outside)*0.9:
        return image, (0, 0)
    sx, sy = image.width / small.width, image.height / small.height
    margin = max(8, round(min(w*sx, h*sy) * 0.02))
    left, top = max(0, round(x*sx)-margin), max(0, round(y*sy)-margin)
    right, bottom = min(image.width, round((x+w)*sx)+margin), min(image.height, round((y+h)*sy)+margin)
    return image.crop((left, top, right, bottom)), (left, top)


def _layout_recovery(image: Image.Image, adaptive=False) -> list[TextBlock]:
    """Read separated text regions in difficult tables; keep photo coordinates.

    Table borders and editor rulers can overwhelm whole-page segmentation.
    Remove long rules, identify glyph-sized components, and pack their regions
    with generous whitespace for one OCR call. No document names/labels enter
    this process. Regions are mapped back before classification or form filling.
    """
    import cv2
    import numpy as np
    import pytesseract

    gray, offset = _page_crop(image.convert("L"))
    gray = _flatten_lighting(_clear_background(_light_background(gray)))
    scale = max(1.0, 2000 / gray.width)
    # Bound the working image for large phone uploads and low-memory servers.
    scale = min(scale, 3600 / max(gray.size))
    gray = gray.resize((round(gray.width * scale), round(gray.height * scale)), Image.Resampling.LANCZOS)
    original_size = gray.size
    angle = _skew_angle(gray)
    if abs(angle) >= 1.5:
        gray = gray.rotate(angle, Image.Resampling.BICUBIC, expand=True, fillcolor=255)
    else:
        angle = 0.0
    array = np.asarray(gray)
    if adaptive:
        ink = cv2.adaptiveThreshold(array, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                   cv2.THRESH_BINARY_INV, 51, 15)
    else:
        _, ink = cv2.threshold(array, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)
    # Erase anti-aliased rule edges as well as their dark centers.
    horizontal = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((1, 80), "uint8"))
    vertical = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((80, 1), "uint8"))
    rules = cv2.dilate(cv2.bitwise_or(horizontal, vertical), np.ones((3, 3), "uint8"))
    ink[rules != 0] = 0
    count, labels, stats, _ = cv2.connectedComponentsWithStats(ink)
    keep = np.zeros(count, dtype="uint8")
    heights = []
    for i, (x, y, w, h, area) in enumerate(stats[1:], 1):
        if h < 7 or w < 2 or area < 12 or h > 180 or (w > gray.width * 0.25 and w > h * 18):
            continue
        keep[i] = 255
        heights.append(int(h))
    if not heights:
        return []
    ink = keep[labels]
    joined = cv2.dilate(ink, np.ones((3, max(6, round(median(heights)))), "uint8"))
    count, _, regions, _ = cv2.connectedComponentsWithStats(joined)
    boxes = []
    for x, y, w, h, area in regions[1:]:
        if w > h * 12:
            # A ruler has many narrow ticks but very few glyph-shaped pieces.
            # Full-width sentences have many such pieces and are kept.
            parts = stats[1:]
            glyphs = ((parts[:, 0] >= x) & (parts[:, 0] < x+w) &
                      (parts[:, 1] >= y) & (parts[:, 1] < y+h) &
                      (parts[:, 3] >= h*0.5) & (parts[:, 2] >= h*0.25))
            if np.count_nonzero(glyphs) < max(3, w/h*0.15):
                continue
        if w >= h * 0.5 and 9 <= h <= 180 and np.count_nonzero(ink[y:y+h, x:x+w]) >= 30:
            boxes.append((int(x), int(y), int(w), int(h)))
    boxes.sort(key=lambda b: (b[1], b[0]))
    # Join adjacent fragments on the same baseline before packing. In a heading
    # each word can have a slightly different top; sorting by y alone scrambles
    # "작품 요약서". Wide gaps between independent table cells remain separate.
    joined_boxes = []
    for box in boxes:
        x, y, w, h = box
        matches = []
        for i, (px, py, pw, ph) in enumerate(joined_boxes):
            overlap = min(y+h, py+ph) - max(y, py)
            gap = max(x, px) - min(x+w, px+pw)
            if overlap >= min(h, ph) * 0.6 and gap < max(h, ph) * 1.5:
                matches.append(i)
        if matches:
            i = matches[0]
            px, py, pw, ph = joined_boxes[i]
            left, top = min(x, px), min(y, py)
            joined_boxes[i] = (left, top, max(x+w, px+pw)-left, max(y+h, py+ph)-top)
        else:
            joined_boxes.append(box)
    boxes = []
    for x, y, w, h in joined_boxes:
        parts = stats[1:]
        glyphs = ((parts[:, 0] >= x) & (parts[:, 0] < x+w) &
                  (parts[:, 1] >= y) & (parts[:, 1] < y+h) &
                  (parts[:, 3] >= h*0.5) & (parts[:, 2] >= h*0.25))
        if w > h * 12 and np.count_nonzero(glyphs) < max(3, w/h*0.15):
            continue
        boxes.append((x, y, w, h))
    boxes.sort(key=lambda b: (b[1], b[0]))
    if not 2 <= len(boxes) <= 80:
        return []
    tiles, placements = [], []
    y_cursor = 24
    for x, y, w, h in boxes:
        factor = min(3.0, max(1.0, 42 / h))
        tile = Image.fromarray(255 - ink[y:y+h, x:x+w]).resize((round(w * factor), round(h * factor)), Image.Resampling.LANCZOS)
        tiles.append(tile)
        placements.append((x, y, w, h, factor, y_cursor))
        y_cursor += tile.height + 32
    packed = Image.new("L", (max(tile.width for tile in tiles) + 48, y_cursor), 255)
    for tile, placement in zip(tiles, placements):
        packed.paste(tile, (24, placement[5]))
    recognized = _tesseract_lines(pytesseract, packed, 6, 1)
    result = []
    for line in recognized:
        if not _letters(line.block.text) or (_letters(line.block.text) < 2 and line.conf < 65):
            continue
        letters = _LETTER.findall(line.block.text)
        if line.conf < 60 and max(Counter(letters).values(), default=0) >= max(8, len(letters) * 0.4):
            # Ruler ticks / dotted borders often become dozens of l/1/0 glyphs.
            # Confident identifiers, including repeated digits, are retained.
            continue
        b = line.block.box
        matches = [p for p in placements if p[5] <= b.y + b.height / 2 <= p[5] + round(p[3] * p[4])]
        if len(matches) != 1:
            continue
        x, y, w, h, factor, row = matches[0]
        box = Box(x=round((x + (b.x-24)/factor)/scale), y=round((y + (b.y-row)/factor)/scale),
                  width=max(1, round(b.width/factor/scale)), height=max(1, round(b.height/factor/scale)))
        if angle:
            box = _unrotate_box(box, angle, tuple(v/scale for v in original_size), tuple(v/scale for v in gray.size))
        left, top = max(0, min(image.width-1, box.x + offset[0])), max(0, min(image.height-1, box.y + offset[1]))
        box = Box(x=left, y=top, width=max(1, min(box.width, image.width-left)), height=max(1, min(box.height, image.height-top)))
        result.append(line.block.model_copy(update={"box": box}))
    return _reading_order(result)

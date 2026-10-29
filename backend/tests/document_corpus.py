"""Shared, offline document classification corpus; synthetic text and recorded OCR."""

import json
import unicodedata
from pathlib import Path

from app.models import Box, TextBlock

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


def blocks(pages: list[str]) -> list[TextBlock]:
    return [
        TextBlock(text=text, page=page, box=Box(x=0, y=row * 30, width=700, height=20))
        for page, content in enumerate(pages)
        for row, text in enumerate(content.splitlines())
        if text.strip()
    ]


def cases():
    authored = json.loads((FIXTURES / "document_cases.json").read_text("utf-8"))
    for case in authored["cases"]:
        yield case["id"], case["expected"], blocks(case.get("pages", [case.get("text", "")])), "authored"
    general = json.loads((FIXTURES / "document_generalization.json").read_text("utf-8"))
    for case in general["cases"]:
        yield case["id"], case["expected"], blocks(case.get("pages", [case.get("text", "")])), "generalization"
    recorded = json.loads((FIXTURES / "document_ocr.json").read_text("utf-8"))
    for case in recorded["samples"]:
        yield case["id"], case["expected"], [TextBlock(**b) for b in case["blocks"]], "local_ocr"
    # Keep deployed OCR as recorded, including its damaged headings and fragmented lines.
    for path in sorted((ROOT / "app/test/fixtures").glob("ocr_*_deployed.json")):
        doc = json.loads(path.read_text("utf-8"))
        yield path.stem, "consent", [TextBlock(**b) for b in doc["blocks"]], "deployed_ocr"


def variants(lines: list[TextBlock]):
    yield "original", lines
    transforms = {
        "spaced": lambda s: " ".join(s),
        "nfd": lambda s: unicodedata.normalize("NFD", s),
        "ocr_separators": lambda s: "\u200b".join(s).replace("·", "ㆍ").replace(":", "："),
    }
    for name, transform in transforms.items():
        yield name, [b.model_copy(update={"text": transform(b.text)}) for b in lines]
    page_count = max((b.page for b in lines), default=0) + 1
    yield "repeated_pages", [
        b.model_copy(update={"page": b.page + repeat * page_count})
        for repeat in range(3) for b in lines
    ]

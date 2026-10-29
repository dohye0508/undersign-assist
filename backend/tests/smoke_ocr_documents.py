"""Opt-in local OCR test; render synthetic forms in memory and use real Tesseract.

python backend/tests/smoke_ocr_documents.py [--all] [--output FILE]
Requires Tesseract with kor data. No AI, network, private documents or saved images.
The 18 default cases cover six output classes and privacy appendices/footers.
"""

import argparse
import io
import json
import sys
import textwrap
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageDraw, ImageFont
from app import config
from app.services import doc_reader, llm, ocr
from document_corpus import FIXTURES, ROOT

DEFAULT_CASES = {
    "labor_standard", "housing", "loan_note", "membership",
    "consent_standard", "consent_parent", "consent_application_heading",
    "notice_standard", "notice_trip_consent", "notice_privacy_footer",
    "application_standard", "application_privacy_footer", "application_appendix",
    "summary_standard", "summary_contract_topic", "unknown_receipt",
    "medical_consent", "privacy_notice_only",
}


def render(text: str, compact: bool = False) -> bytes:
    """Two deterministic layouts: full page and a smaller-font, narrower photo."""
    width, font_size, step = (1200, 30, 56) if compact else (1800, 42, 76)
    font = ImageFont.truetype(str(ROOT / "app/assets/fonts/Pretendard-Regular.otf"), font_size)
    title_font = ImageFont.truetype(str(ROOT / "app/assets/fonts/Pretendard-Bold.otf"), font_size + 8)
    rows = [part for line in text.splitlines() for part in textwrap.wrap(line, width=32) or [""]]
    image = Image.new("RGB", (width, max(700, (len(rows) + 4) * step)), "white")
    draw = ImageDraw.Draw(image)
    for index, line in enumerate(rows):
        draw.text((75, 70 + index * step), line, font=title_font if index == 0 else font, fill="black")
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="Render all authored cases, not just the default 18")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    data = json.loads((FIXTURES / "document_cases.json").read_text("utf-8"))
    results = []
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        for case in data["cases"]:
            if not args.all and case["id"] not in DEFAULT_CASES:
                continue
            for layout in ("full", "compact"):
                lines = []
                for page, text in enumerate(case.get("pages", [case.get("text", "")])):
                    recognized = ocr.recognize(render(text, compact=layout == "compact"))
                    lines.extend(b.model_copy(update={"page": page}) for b in recognized.lines)
                kind, scores, _, _ = doc_reader.read(lines)
                result = {"id": case["id"], "layout": layout, "expected": case["expected"],
                          "actual": kind.value, "scores": scores, "text": "\n".join(b.text for b in lines)}
                results.append(result)
                ok = kind.value == case["expected"]
                print(f"{'PASS' if ok else 'FAIL'} {case['id']}/{layout}: {kind.value}", flush=True)
                if not ok:
                    print(result["text"], flush=True)
    failures = sum(r["expected"] != r["actual"] for r in results)
    print(f"Real OCR on synthetic layouts: {len(results) - failures}/{len(results)}")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())

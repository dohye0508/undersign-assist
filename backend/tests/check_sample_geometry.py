"""Check saved OCR boxes against independently transformed title masks.

Use after sample_corpus's everyday scene evaluation. No OCR/API call is made.
This catches a box that is inside the photo but on the wrong side of a rotated
or cropped page, which a simple coordinate-range assertion cannot detect.
"""

import argparse
import io
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from sample_corpus import ROOT, normalize
from smoke_ocr_documents import render


def title_mask(text, profile):
    source = Image.open(io.BytesIO(render(text)))
    font = ImageFont.truetype(str(ROOT / "app/assets/fonts/Pretendard-Bold.otf"), 50)
    mask = Image.new("L", source.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle(draw.textbbox((75, 70), text.splitlines()[0], font=font), fill=255)
    angle = random.Random(2910).uniform(-12, -8)
    paper = mask.rotate(angle, Image.Resampling.BICUBIC, expand=True, fillcolor=0)
    desk = Image.new("L", (paper.width+380, paper.height+300), 0)
    desk.paste(paper, (190, 150))
    distant = Image.new("L", (desk.width*2, desk.height*2), 0)
    distant.paste(desk, (desk.width//2, desk.height//2))
    if profile == "sideways_desk":
        distant = distant.transpose(Image.Transpose.ROTATE_270)
    return distant


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    rows = {r["id"]: r for r in json.loads(args.results.read_text("utf-8"))["results"]}
    fixtures = json.loads((Path(__file__).parent / "fixtures/document_generalization.json").read_text("utf-8"))["cases"]
    checked = 0
    for case in [c for c in fixtures if c["id"] in ("g_labor", "g_loan", "g_notice", "g_summary")]:
        for profile in ("distant_desk", "sideways_desk"):
            ident = f"everyday_text/{case['id']}/{profile}"
            row = rows[ident]
            title = normalize(case["text"].splitlines()[0])
            matches = [b for b in row["blocks"] if title in normalize(b["text"])]
            assert len(matches) == 1, f"{ident}: title not uniquely recognized"
            truth = title_mask(case["text"], profile)
            photo = Image.open(ROOT / "samples/regression" / (ident + ".jpg"))
            assert truth.size == photo.size, f"{ident}: fixture geometry changed"
            left, top, right, bottom = truth.getbbox()
            box = matches[0]["box"]
            x, y, w, h = [box[k] for k in ("x", "y", "width", "height")]
            intersection = max(0, min(right, x+w)-max(left, x)) * max(0, min(bottom, y+h)-max(top, y))
            iou = intersection / ((right-left)*(bottom-top) + w*h - intersection)
            assert iou >= 0.65, f"{ident}: box on wrong pixels (IoU={iou:.3f})"
            print(f"{ident}: title IoU={iou:.3f}")
            checked += 1
    print(f"{checked}/8 title locations match transformed source pixels")


if __name__ == "__main__":
    main()

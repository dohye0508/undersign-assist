"""Harder reproducible scenes; classification AND transcript error, no cloud calls.

Development/holdout use disjoint authored texts and different transform seeds.
Samples reuse the repository's example images (including filled contract), not
independent field photographs. Their saved OCR is not a ground-truth transcript.
"""

import argparse
import io
import json
import math
import os
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("OMP_THREAD_LIMIT", "1")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps
from app import config
from app.services import doc_reader, llm, ocr
from app.services.doc_classifier import normalize
from smoke_ocr_documents import ROOT, render

PROFILES = ("clean", "tilted", "handheld", "desk", "columns", "grid",
            "dark_screen", "screen_moire", "crease", "pen_marks", "body_blurred")
DEVELOPMENT = {"g_labor", "g_notice", "g_consent", "g_application", "g_summary", "g_receipt"}


def layout(text, profile):
    if profile not in ("columns", "grid"):
        return Image.open(io.BytesIO(render(text))).convert("RGB")
    rows = text.splitlines()
    font = ImageFont.truetype(str(ROOT / "app/assets/fonts/Pretendard-Regular.otf"), 34)
    image = Image.new("RGB", (1800, max(800, 200 + len(rows) * 80)), "white")
    draw = ImageDraw.Draw(image)
    draw.text((80, 65), rows[0], fill="black", font=font)
    if profile == "columns":
        split = math.ceil((len(rows) - 1) / 2)
        for i, row in enumerate(rows[1:]):
            draw.text((80 + (i // split) * 850, 180 + (i % split) * 90), row, font=font, fill="black")
    else:
        for i, row in enumerate(rows[1:]):
            y = 160 + i * 80
            draw.rectangle((65, y, 1735, y + 80), fill="#dddddd" if i % 2 == 0 else "white", outline="#555555", width=3)
            key, sep, value = row.partition(":")
            draw.text((85, y + 20), key, fill="black", font=font)
            if sep:
                draw.line((550, y, 550, y + 80), fill="#555555", width=3)
                draw.text((575, y + 20), value, fill="black", font=font)
    return image


def scene(image, profile, seed):
    rng = random.Random(seed)
    image = image.copy()
    width, height = image.size
    quality = 88
    if profile == "tilted":
        image = image.rotate(rng.choice((-1, 1)) * rng.uniform(11, 15), Image.Resampling.BICUBIC, expand=True, fillcolor="white")
    elif profile == "handheld":
        image = image.transform(image.size, Image.Transform.PERSPECTIVE,
                                (1, 0.09, -20, 0.015, 1, -10, 0.00006, 0.00003),
                                Image.Resampling.BICUBIC, fillcolor="white")
        gradient = Image.linear_gradient("L").rotate(90).resize(image.size).point(lambda p: 65 + p * 160 // 255)
        image = ImageChops.multiply(image, gradient.convert("RGB"))
        image = image.rotate(rng.uniform(8, 12), Image.Resampling.BICUBIC, expand=True, fillcolor="#777777")
        image.thumbnail((1150, 1500), Image.Resampling.LANCZOS)
        image = image.filter(ImageFilter.GaussianBlur(0.55))
        quality = 38
    elif profile == "desk":
        paper = image.rotate(rng.uniform(-12, -8), Image.Resampling.BICUBIC, expand=True, fillcolor="#665544")
        image = Image.new("RGB", (paper.width + 380, paper.height + 300), "#665544")
        draw = ImageDraw.Draw(image)
        for y in range(0, image.height, 34):
            draw.line((0, y, image.width, y + 10), fill="#705c48", width=4)
        image.paste(paper, (190, 150))
    elif profile == "dark_screen":
        image = ImageOps.invert(image)
        image = ImageEnhance.Contrast(image).enhance(0.85)
    elif profile == "screen_moire":
        draw = ImageDraw.Draw(image)
        for y in range(0, height, 5):
            draw.line((0, y, width, y), fill="#b8b8b8", width=1)
        image = image.rotate(3, Image.Resampling.BICUBIC, expand=True, fillcolor="white")
        quality = 55
    elif profile == "crease":
        shade = Image.new("L", image.size, 255)
        draw = ImageDraw.Draw(shade)
        center = int(width * rng.uniform(0.35, 0.6))
        for dx in range(-70, 71):
            draw.line((center + dx, 0, center + dx + 70, height), fill=int(130 + 125 * abs(dx) / 70))
        image = ImageChops.multiply(image, shade.convert("RGB"))
    elif profile == "pen_marks":
        # Synthetic blue annotations, not a handwriting-recognition benchmark.
        draw = ImageDraw.Draw(image)
        for _ in range(4):
            x, y = rng.randrange(width // 3, width - 250), rng.randrange(140, height - 100)
            draw.line([(x, y), (x + 30, y + 25), (x + 75, y - 20)], fill="#1648aa", width=5)
        draw.ellipse((width - 330, height - 220, width - 160, height - 70), outline="#bb3344", width=7)
    elif profile == "body_blurred":
        # A legible title must not conceal a destroyed body.
        body = image.crop((0, 145, width, height)).filter(ImageFilter.GaussianBlur(9))
        image.paste(body, (0, 145))
    output = io.BytesIO()
    image.save(output, "JPEG", quality=quality)
    return output.getvalue()


def edit_distance(reference, actual):
    previous = list(range(len(actual) + 1))
    for i, expected in enumerate(reference, 1):
        current = [i]
        for j, found in enumerate(actual, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (expected != found)))
        previous = current
    return previous[-1]


def run_case(case, profile, seed, module):
    started = time.perf_counter()
    source = Image.open(ROOT / case["source"]).convert("RGB") if "source" in case else layout(case["text"], profile)
    result = module.recognize(scene(source, profile, seed))
    classified = doc_reader.CLASSIFIER.classify(result.lines)
    valid = all(0 <= b.box.x < result.width and 0 <= b.box.y < result.height and b.box.width > 0 and b.box.height > 0
                and b.box.x + b.box.width <= result.width and b.box.y + b.box.height <= result.height for b in result.lines)
    reference = normalize(case.get("text", ""))
    actual = normalize(result.full_text)
    return {"id": case["id"], "profile": profile, "expected": case["expected"], "actual": classified.doc_type.value,
            "expected_review": profile == "body_blurred", "needs_review": getattr(result, "needs_review", False),
            "valid_boxes": valid, "seconds": round(time.perf_counter() - started, 3),
            "reference_characters": len(reference), "edits": edit_distance(reference, actual) if reference else None,
            "text": result.full_text, "blocks": [b.model_dump() for b in result.lines]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suite", choices=("development", "holdout", "samples"), default="development")
    parser.add_argument("--profiles", nargs="+", choices=PROFILES, default=list(PROFILES))
    parser.add_argument("--baseline-ref")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--require-correct", action="store_true", help="Fail on type/box/review mismatch; exploration otherwise")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    module = ocr
    if args.baseline_ref:
        import subprocess
        import types
        revision = subprocess.check_output(["git", "rev-parse", "--verify", args.baseline_ref + "^{commit}"], cwd=ROOT, text=True).strip()
        module = types.ModuleType("_realistic_baseline_ocr")
        sys.modules[module.__name__] = module
        source = subprocess.check_output(["git", "show", revision + ":backend/app/services/ocr.py"], cwd=ROOT).decode("utf-8")
        exec(compile(source, "baseline_ocr.py", "exec"), module.__dict__)
        classifier = types.ModuleType("_realistic_baseline_classifier")
        sys.modules[classifier.__name__] = classifier
        source = subprocess.check_output(["git", "show", revision + ":backend/app/services/doc_classifier.py"], cwd=ROOT).decode("utf-8")
        exec(compile(source, "baseline_classifier.py", "exec"), classifier.__dict__)
        rules = json.loads(subprocess.check_output(["git", "show", revision + ":backend/app/rules/doc_types.json"], cwd=ROOT).decode("utf-8"))
        doc_reader.CLASSIFIER = classifier.DocumentClassifier(rules)
    fixtures = Path(__file__).parent / "fixtures"
    if args.suite == "samples":
        cases = json.loads((fixtures / "document_ocr.json").read_text("utf-8"))["samples"]
        # Identical consent_school.png and 인곽.png count once.
        cases = [case for case in cases if case["id"] != "consent_school.png"]
        profiles = [p for p in args.profiles if p not in ("columns", "grid", "body_blurred")]
    else:
        cases = json.loads((fixtures / "document_generalization.json").read_text("utf-8"))["cases"][:16]
        cases = [c for c in cases if (c["id"] in DEVELOPMENT) == (args.suite == "development")]
        profiles = args.profiles
    seed = 714 if args.suite == "development" else 1903
    results = []
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(run_case, case, profile, seed, module) for case in cases for profile in profiles]
            for future in as_completed(futures):
                row = future.result()
                results.append(row)
                print(f"{len(results)}/{len(futures)} {row['id']}/{row['profile']} {row['expected']}->{row['actual']} review={row['needs_review']}", flush=True)
    results.sort(key=lambda r: (r["id"], r["profile"]))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    good = [r for r in results if not r["expected_review"]]
    characters = sum(r["reference_characters"] for r in good)
    correct = sum(r["expected"] == r["actual"] for r in good)
    edits = sum(r["edits"] or 0 for r in good)
    print(f"types={correct}/{len(good)} CER={edits / characters if characters else 'N/A'} boxes={sum(r['valid_boxes'] for r in results)}/{len(results)}")
    errors = any(not r["valid_boxes"] or (not r["needs_review"] if r["expected_review"] else r["actual"] != r["expected"]) for r in results)
    return int(args.require_correct and errors)


if __name__ == "__main__":
    sys.exit(main())

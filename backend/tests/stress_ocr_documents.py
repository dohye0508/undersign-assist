"""Reproducible camera-condition matrix using local Tesseract, without cloud calls.

python backend/tests/stress_ocr_documents.py --output work/camera.json
All fixtures and all transforms are synthetic. Unknown counts as an abstention,
not a correct classification, for a supported document. Never claim population
accuracy from this development matrix.
"""

import argparse
import io
import json
import os
import random
import subprocess
import sys
import time
import types
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("OMP_THREAD_LIMIT", "1")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter
from app import config
from app.services import doc_reader, llm, ocr
from smoke_ocr_documents import ROOT, render

PROFILES = (
    "clean", "skew", "low_resolution", "blur", "shadow", "perspective",
    "jpeg", "table", "sideways", "sideways_other", "upside_down", "exif", "cropped_title", "combined", "noise",
)


def photograph(text: str, profile: str) -> bytes:
    image = Image.open(io.BytesIO(render(text))).convert("RGB")
    width, height = image.size
    quality = 92
    exif = None
    if profile == "skew":
        image = image.rotate(5, Image.Resampling.BICUBIC, expand=True, fillcolor="white")
    elif profile == "low_resolution":
        image = image.resize((600, round(height * 600 / width)), Image.Resampling.LANCZOS)
    elif profile == "blur":
        image = image.filter(ImageFilter.GaussianBlur(1.5))
    elif profile in ("shadow", "combined"):
        gradient = Image.linear_gradient("L").rotate(90).resize(image.size)
        gradient = gradient.point(lambda p: 75 + p * 150 // 255).convert("RGB")
        image = ImageChops.multiply(image, gradient)
        image = ImageEnhance.Contrast(image).enhance(0.6)
        if profile == "combined":
            image = image.filter(ImageFilter.GaussianBlur(0.7))
            quality = 35
    elif profile == "perspective":
        image = image.transform(image.size, Image.Transform.PERSPECTIVE,
                                (1, 0.07, -20, 0.02, 1, -10, 0.00005, 0.00002),
                                Image.Resampling.BICUBIC, fillcolor="white")
    elif profile == "jpeg":
        quality = 15
    elif profile == "table":
        draw = ImageDraw.Draw(image)
        for y in range(55, height - 70, 76):
            draw.line((55, y, width - 55, y), fill="#777777", width=2)
        draw.rectangle((55, 55, width - 55, height - 70), outline="#777777", width=2)
    elif profile in ("sideways", "exif"):
        image = image.transpose(Image.Transpose.ROTATE_90)
        if profile == "exif":
            exif = Image.Exif()
            exif[274] = 6
    elif profile == "sideways_other":
        image = image.transpose(Image.Transpose.ROTATE_270)
    elif profile == "upside_down":
        image = image.transpose(Image.Transpose.ROTATE_180)
    elif profile == "noise":
        rng = random.Random(20261029)
        draw = ImageDraw.Draw(image)
        for _ in range(4000):
            x, y = rng.randrange(width), rng.randrange(height)
            draw.point((x, y), fill=rng.choice(("#000000", "#ffffff", "#777777")))
    elif profile == "cropped_title":
        image = image.crop((0, 135, width, height))
    output = io.BytesIO()
    options = {"exif": exif} if exif else {}
    image.save(output, "JPEG", quality=quality, **options)
    return output.getvalue()


def run_case(case, profile):
    started = time.perf_counter()
    lines, dimensions = [], []
    for page, text in enumerate(case.get("pages", [case.get("text", "")])):
        result = ocr.recognize(photograph(text, profile))
        dimensions.append([result.width, result.height])
        lines.extend(b.model_copy(update={"page": page}) for b in result.lines)
    classification = doc_reader.CLASSIFIER.classify(lines)
    valid_boxes = all(0 <= b.box.x < dimensions[b.page][0] and 0 <= b.box.y < dimensions[b.page][1]
                      and b.box.width > 0 and b.box.height > 0
                      and b.box.x + b.box.width <= dimensions[b.page][0]
                      and b.box.y + b.box.height <= dimensions[b.page][1] for b in lines)
    return {"id": case["id"], "profile": profile, "expected": case["expected"],
            "actual": classification.doc_type.value, "reason": classification.reason,
            "seconds": round(time.perf_counter() - started, 3), "valid_boxes": valid_boxes,
            "dimensions": dimensions, "blocks": [b.model_dump() for b in lines]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--profiles", nargs="+", choices=PROFILES, default=list(PROFILES))
    parser.add_argument("--cases", nargs="+")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--baseline-ref", help="Use OCR, classification and rules from this local Git commit")
    args = parser.parse_args()
    if args.baseline_ref:
        # Resolve to a commit first. Arguments are passed without a shell.
        revision = subprocess.check_output(["git", "rev-parse", "--verify", args.baseline_ref + "^{commit}"], cwd=ROOT, text=True).strip()

        def source(path):
            return subprocess.check_output(["git", "show", revision + ":" + path], cwd=ROOT).decode("utf-8")

        def load(name, path):
            module = types.ModuleType(name)
            sys.modules[name] = module
            exec(compile(source(path), path, "exec"), module.__dict__)
            return module

        global ocr
        ocr = load("_baseline_ocr", "backend/app/services/ocr.py")
        classifier = load("_baseline_classifier", "backend/app/services/doc_classifier.py")
        doc_reader.CLASSIFIER = classifier.DocumentClassifier(json.loads(source("backend/app/rules/doc_types.json")))
    corpus = json.loads((Path(__file__).parent / "fixtures/document_generalization.json").read_text("utf-8"))["cases"]
    if args.cases and set(args.cases) - {c["id"] for c in corpus}:
        parser.error("Unknown case id; see fixtures/document_generalization.json")
    if args.workers < 1:
        parser.error("--workers must be positive")
    cases = [c for c in corpus if c["id"] in args.cases] if args.cases else corpus[:16]
    results = []
    started = time.perf_counter()
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(run_case, case, profile) for case in cases for profile in args.profiles]
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                if result["actual"] != result["expected"] or not result["valid_boxes"]:
                    print(f"FAIL {result['id']}/{result['profile']}: {result['expected']} -> {result['actual']}", flush=True)
                elif len(results) % 12 == 0:
                    print(f"completed {len(results)}/{len(futures)}", flush=True)
    results.sort(key=lambda r: (r["id"], r["profile"]))
    correct = sum(r["actual"] == r["expected"] for r in results)
    wrong_type = sum(r["actual"] not in (r["expected"], "unknown") for r in results)
    print(f"exact={correct}/{len(results)} wrong_type={wrong_type} elapsed={time.perf_counter() - started:.1f}s")
    for profile in args.profiles:
        rows = [r for r in results if r["profile"] == profile]
        print(profile, dict(Counter("correct" if r["actual"] == r["expected"] else "abstain" if r["actual"] == "unknown" else "wrong" for r in rows)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return int(correct != len(results) or not all(r["valid_boxes"] for r in results))


if __name__ == "__main__":
    sys.exit(main())

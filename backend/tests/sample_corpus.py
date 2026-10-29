"""Save and replay OCR fixtures under samples/regression (no cloud calls).

generate freezes image bytes, labels and hashes; evaluate reads ONLY those bytes.
Original samples stay in place. All derived photographs are simulations.
"""

import argparse
import hashlib
import io
import json
import subprocess
import sys
import time
import types
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

from realistic_ocr_documents import (
    DEVELOPMENT, PROFILES, ROOT, config, doc_reader, edit_distance, layout, llm,
    normalize, ocr, scene,
)
from stress_ocr_documents import PROFILES as CAMERA_PROFILES, photograph
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

DEST = ROOT / "samples/regression"
EXTRA_PROFILES = ("distant_desk", "finger_margin", "faded_copy", "motion_blur",
                  "sideways_desk", "hard_shadow", "body_glare", "tiny_unreadable")


def extra_scene(image, profile):
    image = image.copy()
    w, h = image.size
    if profile in ("distant_desk", "sideways_desk"):
        image = Image.open(io.BytesIO(scene(image, "desk", 2910))).convert("RGB")
        framed = Image.new("RGB", (image.width * 2, image.height * 2), "#665544")
        framed.paste(image, (image.width // 2, image.height // 2))
        image = framed
        if profile == "sideways_desk":
            image = image.transpose(Image.Transpose.ROTATE_270)
    elif profile == "finger_margin":
        # Covers only the margin: no invented handwriting or hidden text.
        ImageDraw.Draw(image).ellipse((-w // 12, h // 2, w // 30, h * 3 // 4), fill="#bd927c")
    elif profile == "faded_copy":
        image = ImageEnhance.Contrast(image).enhance(0.35)
        image = ImageEnhance.Brightness(image).enhance(1.22)
    elif profile == "motion_blur":
        shifted = Image.new("RGB", image.size, "white")
        shifted.paste(image, (3, 1))
        image = Image.blend(image, shifted, 0.5)
    elif profile == "hard_shadow":
        mask = Image.new("L", image.size, 255)
        ImageDraw.Draw(mask).polygon([(0, 0), (w // 2, 0), (w * 3 // 4, h), (0, h)], fill=90)
        mask = mask.filter(ImageFilter.GaussianBlur(8))
        image = ImageChops.multiply(image, mask.convert("RGB"))
    elif profile == "body_glare":
        # Entire body is gone; a title alone must not enable form completion.
        ImageDraw.Draw(image).rectangle((0, 145, w, h), fill="white")
    elif profile == "tiny_unreadable":
        image.thumbnail((180, 220), Image.Resampling.LANCZOS)
        image = image.filter(ImageFilter.GaussianBlur(1.3))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=70)
    return buffer.getvalue()


def generate():
    fixtures = Path(__file__).parent / "fixtures"
    authored = json.loads((fixtures / "document_generalization.json").read_text("utf-8"))["cases"][:16]
    originals = json.loads((fixtures / "document_ocr.json").read_text("utf-8"))["samples"]
    originals = [c for c in originals if c["id"] != "consent_school.png"]
    manifest = []

    def save(case, suite, profile, payload, seed=None):
        # Stable ASCII paths; source retains the original Unicode filename.
        ident = case["id"] if "source" not in case else f"original_{originals.index(case) + 1:02d}"
        relative = f"{suite}/{ident}/{profile}.jpg"
        path = DEST / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        with Image.open(io.BytesIO(payload)) as image:
            dimensions = list(image.size)
        manifest.append({"id": f"{suite}/{ident}/{profile}", "image": relative,
                         "suite": suite, "case": case["id"], "profile": profile,
                         "source": case.get("source", "backend/tests/fixtures/document_generalization.json#" + case["id"]),
                         "seed": seed, "sha256": hashlib.sha256(payload).hexdigest(),
                         "dimensions": dimensions, "expected": case["expected"],
                         "expected_review": profile in ("body_blurred", "body_glare", "tiny_unreadable"),
                         "reference": case.get("text") if profile not in ("cropped_title", "body_blurred", "body_glare", "tiny_unreadable") else None})

    for case in authored:
        for profile in CAMERA_PROFILES:
            save(case, "camera", profile, photograph(case["text"], profile), 20261029)
        suite = "development" if case["id"] in DEVELOPMENT else "holdout"
        seed = 714 if suite == "development" else 1903
        for profile in PROFILES:
            save(case, suite, profile, scene(layout(case["text"], profile), profile, seed), seed)
        for profile in EXTRA_PROFILES:
            save(case, "everyday_text", profile, extra_scene(layout(case["text"], "clean"), profile), 2910)
    for case in originals:
        image = Image.open(ROOT / case["source"]).convert("RGB")
        for profile in PROFILES:
            if profile not in ("columns", "grid", "body_blurred"):
                save(case, "originals", profile, scene(image, profile, 1903), 1903)
        for profile in EXTRA_PROFILES:
            # Original screenshots have variable header positions; don't pretend
            # y=145 is their header/body boundary or assign false negative labels.
            if profile not in ("body_glare", "tiny_unreadable"):
                save(case, "everyday_originals", profile, extra_scene(image, profile), 2910)
    document = {"version": 1, "provenance": "Synthetic transforms of authored fixtures and repository examples; not field photographs. Duplicate consent_school.png/인곽.png counted once.",
                "generated_with": {"pillow": Image.__version__}, "cases": manifest}
    (DEST / "manifest.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(manifest)} images to {DEST}")


def baseline(ref):
    revision = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"], cwd=ROOT, text=True).strip()
    def load(name, path):
        module = types.ModuleType(name)
        sys.modules[name] = module
        content = subprocess.check_output(["git", "show", revision + ":" + path], cwd=ROOT).decode("utf-8")
        exec(compile(content, path, "exec"), module.__dict__)
        return module
    module = load("_saved_baseline_ocr", "backend/app/services/ocr.py")
    classifier = load("_saved_baseline_classifier", "backend/app/services/doc_classifier.py")
    rules = json.loads(subprocess.check_output(["git", "show", revision + ":backend/app/rules/doc_types.json"], cwd=ROOT).decode("utf-8"))
    return module, classifier.DocumentClassifier(rules), revision


def evaluate(case, module, classifier):
    payload = (DEST / case["image"]).read_bytes()
    if hashlib.sha256(payload).hexdigest() != case["sha256"]:
        raise ValueError(f"Fixture changed: {case['image']}; regenerate manifest explicitly")
    started = time.perf_counter()
    result = module.recognize(payload)
    classified = classifier.classify(result.lines).doc_type.value
    reference = normalize(case.get("reference") or "")
    valid = all(0 <= b.box.x < result.width and 0 <= b.box.y < result.height and b.box.width > 0 and b.box.height > 0
                and b.box.x + b.box.width <= result.width and b.box.y + b.box.height <= result.height for b in result.lines)
    return {"id": case["id"], "expected": case["expected"], "actual": classified,
            "expected_review": case["expected_review"], "needs_review": result.needs_review,
            "valid_boxes": valid, "seconds": round(time.perf_counter() - started, 3),
            "reference_characters": len(reference), "edits": edit_distance(reference, normalize(result.full_text)) if reference else None,
            "text": result.full_text, "blocks": [b.model_dump() for b in result.lines]}


def catalog():
    cases = json.loads((DEST / "manifest.json").read_text("utf-8"))["cases"]
    for name in ("before", "after"):
        paths = sorted((DEST / "results").glob(f"{name}*.json"))
        rows = [r for path in paths for r in json.loads(path.read_text("utf-8"))["results"]]
        lookup = {r["id"]: r for r in rows}
        if len(lookup) != len(rows):
            raise ValueError(f"Duplicate results in {name} files; keep one measurement per image")
        for case in cases:
            row = lookup.get(case["id"])
            case[name] = {k: row[k] for k in ("actual", "needs_review", "text", "seconds")} if row else None
    payload = json.dumps(cases, ensure_ascii=False).replace("<", "\\u003c")
    template = Path(__file__).with_name("sample_catalog.html").read_text("utf-8")
    rendered = template.replace("__FIXTURE_DATA__", payload).replace("__FIXTURE_COUNT__", str(len(cases)))
    (DEST.parent / "index.html").write_text(rendered, encoding="utf-8")
    print(f"Catalog: {DEST.parent / 'index.html'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("generate", "evaluate", "catalog"))
    parser.add_argument("--suites", nargs="+")
    parser.add_argument("--cases", nargs="+", help="Original fixture IDs, including Unicode names")
    parser.add_argument("--profiles", nargs="+")
    parser.add_argument("--baseline-ref")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--require-correct", action="store_true")
    args = parser.parse_args()
    if args.command == "generate":
        generate()
        catalog()
        return 0
    if args.command == "catalog":
        catalog()
        return 0
    if not args.output or args.workers < 1:
        parser.error("evaluate requires --output and positive --workers")
    cases = json.loads((DEST / "manifest.json").read_text("utf-8"))["cases"]
    for field, values in (("suite", args.suites), ("case", args.cases), ("profile", args.profiles)):
        if values:
            if set(values) - {c[field] for c in cases}:
                parser.error(f"Unknown {field}: {set(values) - {c[field] for c in cases}}")
            cases = [c for c in cases if c[field] in values]
    if not cases:
        parser.error("No matching fixtures")
    module, classifier, revision = baseline(args.baseline_ref) if args.baseline_ref else (ocr, doc_reader.CLASSIFIER, "working-tree")
    results = []
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(evaluate, c, module, classifier) for c in cases]
            for future in as_completed(futures):
                row = future.result()
                results.append(row)
                if len(results) % 12 == 0:
                    print(f"{len(results)}/{len(cases)}", flush=True)
    results.sort(key=lambda r: r["id"])
    ordinary = [r for r in results if not r["expected_review"]]
    negatives = [r for r in results if r["expected_review"]]
    stats = {"count": len(results), "type_correct": sum(r["expected"] == r["actual"] for r in ordinary),
             "ordinary": len(ordinary), "usable": sum(r["expected"] == r["actual"] and not r["needs_review"] for r in ordinary),
             "false_review": sum(r["needs_review"] for r in ordinary),
             "negative_detected": sum(r["needs_review"] for r in negatives), "negatives": len(negatives),
             "invalid_boxes": sum(not r["valid_boxes"] for r in results)}
    chars = sum(r["reference_characters"] for r in ordinary)
    stats["cer"] = sum(r["edits"] or 0 for r in ordinary) / chars if chars else None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"revision": revision, "stats": stats, "results": results}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False), flush=True)
    return int(args.require_correct and (stats["usable"] != len(ordinary) or stats["negative_detected"] != len(negatives) or stats["invalid_boxes"]))


if __name__ == "__main__":
    sys.exit(main())

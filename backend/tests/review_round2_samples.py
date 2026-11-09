"""Frozen real-OCR regression for mixed pages and identity ownership; no API calls."""
import argparse
import hashlib
import html
import json
import subprocess
import sys
import types
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from stress_ocr_documents import ROOT, photograph, config, ocr, doc_reader, llm
from test_multipage_review import FORMS, PRIVACY, body
from app.services.doc_classifier import normalize

DEST = ROOT / "samples/review-round2"
BASELINE = "a6291b10a13355da3ea748c01f66e54c44e5d028"


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf-8")


def generate():
    forms = [
        ("privacy_appendix", "authorization", [body("authorization"), PRIVACY], {}),
        ("mixed_cropped", "unknown", [FORMS["authorization"], body("receipt")], {}),
        ("reference_appendix", "unknown", ["보관 메모\n관리번호: 123\n이 자료는 작성 방법을 설명하기 위한 참고 자료입니다\n실제로 제출하는 서식이 아닙니다", "청구서 작성 가이드\n" + body("invoice")], {}),
        ("certificate_subject", "certificate", ["재직증명서\n대표자 성명: 박대표\n대표자 연락처: 02-123-4567\n신청인 성명: 김신청\n신청인 소속: 예시회사 개발팀\n재직 기간: 2024년 3월부터 현재\n발급 기관: 예시회사\n발급일: 2026년 11월 9일\n위 사실을 증명합니다."], {"성명": "김신청", "소속": "예시회사 개발팀"}),
        ("applicant_contact", "application", ["체험학습 참가 신청서\n보호자 성명: 박보호\n담당자 연락처: 02-123-4567\n신청인 성명: 김신청\n신청인 연락처: 010-1111-2222\n소속: 예시학교\n참가 부문: 역사 탐방\n신청합니다."], {"성명": "김신청", "연락처": "010-1111-2222"}),
    ]
    cases = []
    for ident, expected, texts, fields in forms:
        for profile in ("clean", "skew"):
            images = []
            for page, text in enumerate(texts):
                payload = photograph(text, profile)
                name = f"images/{ident}/{profile}-{page+1}.jpg"
                path = DEST / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
                images.append({"path": name, "sha256": hashlib.sha256(payload).hexdigest(), "text": text})
            cases.append({"id": f"{ident}/{profile}", "expected": expected, "fields": fields, "images": images})
    save(DEST / "manifest.json", {"provenance": "Authored synthetic forms, clean and 5-degree skew. Not field photos.", "cases": cases})


def old_classifier():
    def source(path):
        return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT).decode("utf-8")
    module = types.ModuleType("_review2_before")
    sys.modules[module.__name__] = module
    exec(compile(source("backend/app/services/doc_classifier.py"), "before.py", "exec"), module.__dict__)
    return module.DocumentClassifier(json.loads(source("backend/app/rules/doc_types.json")))


def evaluate(case):
    lines, reviews = [], []
    for page, image in enumerate(case["images"]):
        payload = (DEST / image["path"]).read_bytes()
        if hashlib.sha256(payload).hexdigest() != image["sha256"]:
            raise ValueError("Sample changed: " + image["path"])
        result = ocr.recognize(payload)
        lines.extend(b.model_copy(update={"page": page}) for b in result.lines)
        reviews.append(result.needs_review)
    kind, _, fields, _ = doc_reader.read(lines)
    actual_fields = {f.label: f.value for f in fields}
    checks = {label: normalize(actual_fields.get(label, "")) == normalize(value) for label, value in case["fields"].items()}
    return {"id": case["id"], "expected": case["expected"], "actual": kind.value,
            "needs_review": any(reviews), "fields": actual_fields, "field_checks": checks,
            "blocks": [b.model_dump() for b in lines]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("generate", "evaluate"))
    parser.add_argument("--require-correct", action="store_true")
    parser.add_argument("--output", type=Path, default=DEST / "results.json")
    args = parser.parse_args()
    if args.command == "generate":
        generate()
        return 0
    cases = json.loads((DEST / "manifest.json").read_text("utf-8"))["cases"]
    old = old_classifier()
    from app.models import TextBlock
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        with ThreadPoolExecutor(max_workers=3) as pool:
            rows = list(pool.map(evaluate, cases))
    for row in rows:
        row["before"] = old.classify([TextBlock(**b) for b in row["blocks"]]).doc_type.value
    failures = [r for r in rows if r["actual"] != r["expected"] or r["needs_review"] or not all(r["field_checks"].values())]
    save(args.output, {"baseline": BASELINE, "engine": subprocess.check_output([config.TESSERACT_CMD, "--version"], text=True).splitlines()[0],
                               "source_hashes": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                                   "backend/app/services/doc_reader.py", "backend/app/services/doc_classifier.py", "backend/app/rules/doc_types.json", "backend/app/services/ocr.py")},
                               "comparison": "Same real OCR text, before/current classification; current extraction checked separately.", "failures": len(failures), "results": rows})
    report = ["# 추가 검토 실제 OCR 표본", "", "가상 문서 5묶음 × 정면/5도 기울기 = 10건, 이미지 16장. 현장 사진이 아닙니다.",
              "저장한 이미지 해시를 확인하고 실제 Tesseract를 실행했습니다. 같은 OCR 결과로 이전/현재 분류를 비교합니다.", "",
              "|사례|정답|이전|현재|재촬영|지정 항목값|", "|---|---|---|---|---|---|"]
    for row, case in zip(rows, cases):
        links = " · ".join(f"[사진{i+1}]({im['path']})" for i, im in enumerate(case["images"]))
        report.append(f"|{row['id']} {links}|{row['expected']}|{row['before']}|{row['actual']}|{row['needs_review']}|{sum(row['field_checks'].values())}/{len(row['field_checks'])}|")
    report += ["", f"분류·재촬영·지정 항목값 조건 중 불일치한 사례: {len(failures)}/10. OCR 원문은 results.json에 보존했습니다.", "",
               "저장된 이미지 그대로 재현: `python backend/tests/review_round2_samples.py evaluate --require-correct`. 문안 변경 시에만 `generate`로 재생성합니다."]
    if args.output.resolve() == (DEST / "results.json").resolve():
        (DEST / "README.md").write_text("\n".join(report) + "\n", "utf-8")
        cards = []
        for row, case in zip(rows, cases):
            pictures = "".join(f'<a href="{im["path"]}"><img loading="lazy" src="{im["path"]}" alt="{html.escape(row["id"])} {i+1}페이지"></a>' for i, im in enumerate(case["images"]))
            transcript = "\n".join(f'[{b["page"]+1}페이지] {b["text"]}' for b in row["blocks"])
            cards.append(f'<article><h2>{html.escape(row["id"])}</h2><p>정답: {row["expected"]} · 이전: {row["before"]} → 현재: {row["actual"]}</p><p>재촬영: {row["needs_review"]} · 지정 항목값 {sum(row["field_checks"].values())}/{len(row["field_checks"])}</p><div class="images">{pictures}</div><details><summary>OCR 원문과 추출 항목</summary><pre>{html.escape(transcript)}</pre><pre>{html.escape(json.dumps(row["fields"], ensure_ascii=False, indent=2))}</pre></details></article>')
        (DEST / "index.html").write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>추가 검토 OCR 표본</title><style>body{font:16px/1.6 sans-serif;max-width:1100px;margin:24px auto;padding:0 16px;background:#f4f6f8;color:#182333}article{background:white;padding:20px;margin:20px 0;border:1px solid #ccd5df;border-radius:12px}.images{display:flex;flex-wrap:wrap;gap:12px}.images img{width:300px;max-width:100%;height:390px;object-fit:contain;border:1px solid #ddd}pre{white-space:pre-wrap;overflow-wrap:anywhere}a{color:#1854a0}</style><h1>추가 검토 실제 OCR 표본</h1><p><a href="../index.html">전체 샘플</a> · <a href="results.json">OCR 기록</a> · <a href="manifest.json">문안·이미지 해시</a></p><p>가상 문서 5묶음 × 정면/5도 기울기 = 10건, 16장. 실제 현장 사진이 아닙니다. 저장한 이미지에 실제 Tesseract를 실행하고, 같은 OCR 원문으로 이전/현재 분류를 비교했습니다.</p><p>분류·재촬영·지정 항목값 조건 불일치: ' + str(len(failures)) + '/10. 지정 항목값은 일부만 검사하며 전체 글자 정확도를 뜻하지 않습니다.</p>' + ''.join(cards) + '</html>\n', 'utf-8')
    print(json.dumps({"documents": len(rows), "images": sum(len(c['images']) for c in cases), "failures": [r['id'] for r in failures]}, ensure_ascii=False), flush=True)
    return int(args.require_correct and bool(failures))


if __name__ == "__main__":
    sys.exit(main())

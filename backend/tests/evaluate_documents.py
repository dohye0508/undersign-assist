"""Offline corpus report: python backend/tests/evaluate_documents.py [--output FILE]."""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services import doc_reader
from document_corpus import cases, variants


def evaluate():
    results = []
    with patch.object(doc_reader.llm, "available", return_value=False):
        for name, expected, lines, source in cases():
            for variant, sample in variants(lines):
                actual, scores, _, _ = doc_reader.read(sample)
                results.append({"id": name, "source": source, "variant": variant,
                                "expected": expected, "actual": actual.value, "scores": scores})
    return results


def report(results, prefix=""):
    for group in ("original", "all"):
        rows = [r for r in results if group == "all" or r["variant"] == group]
        correct = sum(r["expected"] == r["actual"] for r in rows)
        print(f"{prefix}{group}: {correct}/{len(rows)} ({correct / len(rows):.1%})")
    original = [r for r in results if r["variant"] == "original"]
    for source in sorted({r["source"] for r in original}):
        rows = [r for r in original if r["source"] == source]
        print(f"  {source}: {sum(r['expected'] == r['actual'] for r in rows)}/{len(rows)}")
    confusion = Counter((r["expected"], r["actual"]) for r in original if r["expected"] != r["actual"])
    for (expected, actual), count in sorted(confusion.items()):
        print(f"  {expected} -> {actual}: {count}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--failures", action="store_true")
    args = parser.parse_args()
    results = evaluate()
    if args.baseline:
        report(json.loads(args.baseline.read_text("utf-8")), "baseline ")
    report(results, "current ")
    if args.failures:
        for result in results:
            if result["actual"] != result["expected"]:
                print(json.dumps(result, ensure_ascii=False))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

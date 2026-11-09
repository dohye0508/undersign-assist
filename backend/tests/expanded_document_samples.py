"""Saved synthetic document-type corpus, real local OCR, and frozen-text A/B replay.

generate: author 24 different texts and save every image with its SHA256.
ocr: execute Tesseract on saved images (never a mocked OCR or cloud request).
evaluate: feed the identical recorded OCR blocks to old and current classifiers.
An OCR cache is only a replay of an explicitly recorded engine run, not a new run.
"""

import argparse
import hashlib
import html
import io
import json
import subprocess
import sys
import time
import types
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

from realistic_ocr_documents import ROOT, config, doc_reader, layout, llm, normalize, ocr, scene
from stress_ocr_documents import photograph
from sample_corpus import extra_scene
from app.models import TextBlock
from PIL import Image

DEST = ROOT / "samples/document-types"
PROFILES = ("clean", "skew", "desk", "shadow", "blur", "cropped_title", "sideways", "tiny_unreadable")
PROFILE_LABELS = dict(zip(PROFILES, ("정면", "기울기", "책상", "그림자", "흐림", "제목 잘림", "회전", "판독 불가")))
BASELINE = "7263d75a1c259d6139614a198835a3ed4a16f17f"

# Hand-transcribed from the authored source, independent of extraction rules.
# These two fields per form are a bounded spot check, not full-field accuracy.
FIELD_EXPECTATIONS = {
    "authorization_1": {"위임인": "김하늘", "대리인": "이다온"},
    "authorization_2": {"위임인": "박가람", "대리인": "최나래"},
    "authorization_3": {"위임인": "윤초롱", "대리인": "정새봄"},
    "certificate_1": {"성명": "김하늘", "발급 기관": "가상문화센터"},
    "certificate_2": {"성명": "박가람", "발급 기관": "가상중학교"},
    "certificate_3": {"성명": "윤초롱", "발급 기관": "가상교육원"},
    "invoice_1": {"청구 금액": "50000원", "납부 기한": "2026년 11월 20일"},
    "invoice_2": {"청구 금액": "120000원", "납부 기한": "2026년 11월 25일"},
    "invoice_3": {"청구 금액": "80000원", "납부 기한": "2026년 11월 15일"},
    "receipt_1": {"결제 금액": "10000원", "승인 번호": "12345678"},
    "receipt_2": {"결제 금액": "80000원", "승인 번호": "2026110901"},
    "receipt_3": {"결제 금액": "9000원", "승인 번호": "87654321"},
    "pledge_1": {"서약자": "김하늘", "작성일": "2026년 11월 9일"},
    "pledge_2": {"서약자": "박가람", "작성일": "2026년 11월 9일"},
    "pledge_3": {"서약자": "윤초롱", "작성일": "2026년 11월 9일"},
    "report_1": {"보고자": "김하늘", "활동 내용": "전시 시설을 방문했습니다"},
    "report_2": {"보고자": "박가람", "활동 내용": "마을 공원 청소"},
    "report_3": {"보고자": "윤초롱", "활동 내용": "행사 준비물 점검"},
    "questionnaire_1": {"조사 목적": "다음 교육의 운영 개선", "의견": "자유롭게 적어 주세요"},
    "questionnaire_2": {"조사 목적": "시설 이용 환경 개선", "의견": "개선할 점을 적어 주세요"},
    "questionnaire_3": {"조사 목적": "다음 행사 주제 선정", "의견": "희망 활동을 적어 주세요"},
    "activity_consent_1": {"활동명": "과학관 체험", "보호자": "김새봄"},
    "activity_consent_2": {"활동명": "생태 공원 관찰", "보호자": "박다온"},
    "activity_consent_3": {"활동명": "주말 독서 캠프", "보호자": "윤나래"},
}


def authored_cases():
    texts = {
        "authorization": [
            "서류 수령 위임장\n위임인: 김하늘\n수임인: 이다온\n위임 사항: 재학 증명서 수령\n위임 범위: 서류 한 부 수령\n위임 기간: 2026년 11월 9일\n작성일: 2026년 11월 8일\n위임인 서명: 김하늘",
            "민원 업무 위임장\n위임자: 박가람\n대리인: 최나래\n위임 내용: 전입 관련 서류 제출\n위임 범위: 민원 서류 접수\n유효 기간: 2026년 11월 10일까지\n연락처: 010-0000-0000\n작성일: 2026년 11월 9일",
            "물품 수령 위임장\n위임인: 윤초롱\n수임인: 정새봄\n위임 사항: 보관 물품 수령\n위임 범위: 접수번호 103 물품\n위임 기간: 2026년 11월 12일\n대리인 연락처: 010-0000-0000\n작성일: 2026년 11월 11일",
        ],
        "certificate": [
            "재직 증명서\n성명: 김하늘\n소속: 운영지원팀\n직위: 사원\n재직 기간: 2024년 3월부터 현재\n증명 내용: 위 사람의 재직을 증명합니다\n발급 기관: 가상문화센터\n발급일: 2026년 11월 9일\n용도: 본인 확인",
            "재학 증명서\n성명: 박가람\n학교명: 가상중학교\n학년: 2학년\n증명 내용: 현재 재학 중임을 증명합니다\n발급 기관: 가상중학교\n발급일: 2026년 11월 9일\n용도: 교육 프로그램 제출",
            "교육 이수 확인서\n성명: 윤초롱\n교육 과정: 시민 문화 교육\n교육 기간: 2026년 10월 1일부터 30일\n이수 시간: 20시간\n확인 내용: 해당 과정을 이수하였음을 확인합니다\n발급 기관: 가상교육원\n발급일: 2026년 11월 9일",
        ],
        "invoice": [
            "물품 대금 청구서\n청구인: 가상문구\n청구 대상: 가상문화센터\n청구 내역: 문구 세트 10개\n청구 금액: 50000원\n납부 기한: 2026년 11월 20일\n납부 방법: 계좌 이체\n납부 계좌: 테스트은행 000-000-000\n발행일: 2026년 11월 9일",
            "관리비 납부 고지서\n납부자: 김하늘\n고지 내역: 2026년 10월 관리비\n고지 금액: 120000원\n납부 기한: 2026년 11월 25일\n납부 방법: 자동 이체\n발행 기관: 가상관리소\n문의처: 02-000-0000",
            "수강료 청구서\n청구인: 가상교육원\n납부자: 박가람\n청구 내역: 11월 미술 수강료\n청구 금액: 80000원\n납부 기한: 2026년 11월 15일\n납부 방법: 방문 결제\n문의처: 02-000-0000\n발행일: 2026년 11월 9일",
        ],
        "receipt": [
            "물품 구매 영수증\n상호: 가상문구\n거래일: 2026년 11월 9일\n구매 내역: 공책 5권\n결제 금액: 10000원\n결제 방법: 신용카드\n승인 번호: 12345678\n공급가액: 9091원\n부가세: 909원",
            "수강료 납부 영수증\n납부자: 박가람\n수납 기관: 가상교육원\n납부 내역: 11월 미술 수강료\n납부 금액: 80000원\n납부일: 2026년 11월 9일\n결제 방법: 계좌 이체\n영수 번호: 2026110901",
            "현금 영수증\n상호: 가상식당\n거래일: 2026년 11월 9일\n거래 내역: 점심 식사\n결제 금액: 9000원\n결제 방법: 현금\n승인 번호: 87654321\n발행일: 2026년 11월 9일",
        ],
        "pledge": [
            "보안 서약서\n서약자: 김하늘\n소속: 가상문화센터\n서약 내용: 업무 자료를 외부에 공개하지 않겠습니다\n준수 사항: 자료를 허락 없이 복사하지 않습니다\n비밀 유지: 업무상 알게 된 정보를 보호합니다\n서약 기간: 활동 기간 동안\n작성일: 2026년 11월 9일\n서약자 서명: 김하늘",
            "안전 수칙 준수 서약서\n서약자: 박가람\n활동명: 생활 체육 교실\n서약 내용: 활동 중 안전 수칙을 준수합니다\n준수 사항: 보호 장비를 착용합니다\n의무 사항: 위험 상황은 담당자에게 알립니다\n서약 기간: 2026년 11월\n작성일: 2026년 11월 9일\n서약자 서명: 박가람",
            "청렴 서약서\n서약자: 윤초롱\n소속: 가상봉사단\n서약 내용: 업무를 공정하게 수행하겠습니다\n준수 사항: 부당한 청탁을 받지 않습니다\n의무 사항: 이해 관계가 생기면 알립니다\n작성일: 2026년 11월 9일\n서약자 서명: 윤초롱",
        ],
        "report": [
            "현장 방문 결과 보고서\n보고자: 김하늘\n보고일: 2026년 11월 9일\n활동 기간: 2026년 11월 8일\n활동 내용: 전시 시설을 방문했습니다\n활동 결과: 안내 표지를 확인했습니다\n개선 사항: 입구 안내문을 추가합니다\n향후 계획: 다음 달 재방문합니다",
            "봉사 활동 보고서\n작성자: 박가람\n보고일: 2026년 11월 9일\n활동 기간: 2026년 11월 7일\n활동 내용: 마을 공원 청소\n활동 결과: 쓰레기 세 봉지를 수거했습니다\n참여 인원: 8명\n향후 계획: 매월 정기 활동을 진행합니다",
            "업무 결과 보고서\n보고자: 윤초롱\n보고일: 2026년 11월 9일\n업무 내용: 행사 준비물 점검\n추진 실적: 물품 20종을 확인했습니다\n문제점: 안내 책자가 부족합니다\n개선 사항: 안내 책자를 추가 인쇄합니다\n향후 계획: 행사 전 다시 점검합니다",
        ],
        "questionnaire": [
            "교육 만족도 설문지\n조사 목적: 다음 교육의 운영 개선\n응답자: 익명\n질문 1: 교육 내용에 만족하십니까\n응답 항목: 매우 만족, 만족, 보통, 불만족\n질문 2: 교육 시간이 적절했습니까\n선택 항목: 그렇다, 보통이다, 아니다\n기타 의견: 자유롭게 적어 주세요",
            "시설 이용 설문지\n조사 목적: 시설 이용 환경 개선\n응답자: 이용자\n질문 1: 한 달에 몇 번 방문하십니까\n응답 항목: 한 번, 두 번, 세 번 이상\n질문 2: 안내 표지가 이해하기 쉽습니까\n선택 항목: 그렇다, 보통이다, 아니다\n기타 의견: 개선할 점을 적어 주세요",
            "행사 수요 조사서\n조사 목적: 다음 행사 주제 선정\n응답자: 주민\n질문 1: 참여하고 싶은 활동은 무엇입니까\n응답 항목: 미술, 음악, 운동\n질문 2: 참여 가능한 요일은 언제입니까\n선택 항목: 평일, 토요일, 일요일\n기타 의견: 희망 활동을 적어 주세요",
        ],
        "activity_consent": [
            "체험 활동 참가 동의서\n활동명: 과학관 체험\n참가자: 김하늘\n보호자: 김새봄\n활동 일시: 2026년 11월 15일\n활동 장소: 가상과학관\n동의 내용: 위 활동 참가에 동의합니다\n동의 여부: 동의함, 동의하지 않음\n보호자 서명: 김새봄",
            "현장 체험학습 동의서\n활동명: 생태 공원 관찰\n참가 학생: 박가람\n보호자 성명: 박다온\n활동 일시: 2026년 11월 20일\n활동 장소: 가상생태공원\n참가 동의: 체험학습 참가에 동의합니다\n동의 여부: 동의함, 동의하지 않음\n보호자 서명: 박다온",
            "캠프 참가 동의서\n활동명: 주말 독서 캠프\n참가자: 윤초롱\n보호자: 윤나래\n활동 기간: 2026년 11월 21일부터 22일\n활동 장소: 가상수련원\n동의 내용: 캠프 참가에 동의합니다\n동의 여부: 동의함, 동의하지 않음\n보호자 서명: 윤나래",
        ],
    }
    return [{"id": f"{kind}_{index + 1}", "expected": kind, "text": text,
             "provenance": "Authored synthetic example; fictitious names, places and amounts."}
            for kind, examples in texts.items() for index, text in enumerate(examples)]


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def generate():
    cases = authored_cases()
    dump(DEST / "authored.json", cases)
    dump(DEST / "field_expectations.json", FIELD_EXPECTATIONS)
    entries = []
    for index, case in enumerate(cases):
        for profile in PROFILES:
            seed = 20261109 + index
            if profile == "desk":
                payload = scene(layout(case["text"], "clean"), profile, seed)
            elif profile == "tiny_unreadable":
                payload = extra_scene(layout(case["text"], "clean"), profile)
            else:
                payload = photograph(case["text"], profile)
            relative = f"images/{case['id']}/{profile}.jpg"
            path = DEST / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
            with Image.open(io.BytesIO(payload)) as image:
                dimensions = list(image.size)
            entries.append({"id": f"{case['id']}/{profile}", "case": case["id"],
                            "expected": case["expected"], "profile": profile,
                            "expected_review": profile == "tiny_unreadable", "seed": seed,
                            "image": relative, "dimensions": dimensions,
                            "sha256": hashlib.sha256(payload).hexdigest(), "reference": case["text"]})
    dump(DEST / "manifest.json", {"version": 1, "provenance": "24 authored texts with synthetic transformations; NOT independent field photographs.",
                                  "pillow": Image.__version__, "cases": entries})
    print(f"Saved {len(entries)} images, {len(cases)} distinct authored texts", flush=True)


def checked_image(case):
    payload = (DEST / case["image"]).read_bytes()
    if hashlib.sha256(payload).hexdigest() != case["sha256"]:
        raise ValueError(f"Changed sample: {case['image']}")
    return payload


def recognize(case):
    started = time.perf_counter()
    result = ocr.recognize(checked_image(case))
    valid = all(0 <= b.box.x < result.width and 0 <= b.box.y < result.height
                and b.box.width > 0 and b.box.height > 0
                and b.box.x + b.box.width <= result.width and b.box.y + b.box.height <= result.height
                for b in result.lines)
    return {"id": case["id"], "sha256": case["sha256"], "needs_review": result.needs_review,
            "text": result.full_text, "blocks": [b.model_dump() for b in result.lines],
            "dimensions": [result.width, result.height], "valid_boxes": valid,
            "seconds": round(time.perf_counter() - started, 3)}


def run_ocr(cases, workers, output):
    rows = []
    with patch.object(config, "OCR_PROVIDER", "tesseract"), patch.object(llm, "available", return_value=False):
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(recognize, case) for case in cases]
            for future in as_completed(futures):
                row = future.result()
                rows.append(row)
                print(f"{len(rows)}/{len(cases)} {row['id']} review={row['needs_review']}", flush=True)
    engine = subprocess.check_output([config.TESSERACT_CMD, "--version"], text=True).splitlines()[0]
    model = Path(config.TESSERACT_CMD).parent / "tessdata/kor.traineddata"
    dump(output, {"engine": engine, "provider": "tesseract", "cloud_calls": False,
                  "ocr_code_sha256": hashlib.sha256((ROOT / "backend/app/services/ocr.py").read_bytes()).hexdigest(),
                  "kor_model_sha256": hashlib.sha256(model.read_bytes()).hexdigest() if model.exists() else None,
                  "results": sorted(rows, key=lambda row: row["id"])})


def baseline_classifier(ref):
    revision = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"], cwd=ROOT, text=True).strip()
    def source(path):
        return subprocess.check_output(["git", "show", revision + ":" + path], cwd=ROOT).decode("utf-8")
    module = types.ModuleType("_expanded_baseline_classifier")
    sys.modules[module.__name__] = module
    exec(compile(source("backend/app/services/doc_classifier.py"), "baseline_classifier.py", "exec"), module.__dict__)
    return module.DocumentClassifier(json.loads(source("backend/app/rules/doc_types.json"))), revision


def evaluate(cases, cache, output, baseline_ref, require_correct):
    saved = json.loads(cache.read_text("utf-8"))
    ocr_hash = hashlib.sha256((ROOT / "backend/app/services/ocr.py").read_bytes()).hexdigest()
    if saved["ocr_code_sha256"] != ocr_hash:
        raise ValueError("OCR implementation changed since recording; rerun the ocr command explicitly")
    lookup = {row["id"]: row for row in saved["results"]}
    old, revision = baseline_classifier(baseline_ref)
    dump(DEST / "field_expectations.json", FIELD_EXPECTATIONS)
    rows = []
    for case in cases:
        checked_image(case)
        row = lookup[case["id"]]
        if row["sha256"] != case["sha256"]:
            raise ValueError("OCR cache and image hashes differ")
        blocks = [TextBlock.model_validate(b) for b in row["blocks"]]
        before = old.classify(blocks)
        after = doc_reader.CLASSIFIER.classify(blocks)
        # The read route blocks form extraction while an image needs retaking.
        fields = [] if row["needs_review"] else doc_reader._extract_by_rules(blocks, after.doc_type)
        values = {field.label: field.value for field in fields}
        expected_fields = FIELD_EXPECTATIONS[case["case"]]
        field_checks = {label: normalize(value) == normalize(values.get(label, ""))
                        for label, value in expected_fields.items()}
        rows.append({**row, "expected": case["expected"], "profile": case["profile"],
                     "expected_review": case["expected_review"], "before": before.doc_type.value,
                     "after": after.doc_type.value, "reason": after.reason,
                     "fields": [field.model_dump() for field in fields], "field_checks": field_checks})
    ordinary = [r for r in rows if not r["expected_review"]]
    negatives = [r for r in rows if r["expected_review"]]
    stats = {"count": len(rows), "ordinary": len(ordinary),
             "before_correct": sum(r["before"] == r["expected"] for r in ordinary),
             "after_correct": sum(r["after"] == r["expected"] for r in ordinary),
             "usable": sum(r["after"] == r["expected"] and not r["needs_review"] for r in ordinary),
             "with_fields": sum(bool(r["fields"]) and r["after"] == r["expected"] for r in ordinary),
             "field_values_checked": sum(len(r["field_checks"]) for r in ordinary),
             "field_values_correct": sum(sum(r["field_checks"].values()) for r in ordinary),
             "negative_detected": sum(r["needs_review"] for r in negatives), "negatives": len(negatives),
             "invalid_boxes": sum(not r["valid_boxes"] for r in rows)}
    code_hashes = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in (
        "backend/app/services/doc_classifier.py", "backend/app/services/doc_reader.py", "backend/app/rules/doc_types.json")}
    dump(output, {"baseline": revision, "comparison": "Same recorded real OCR blocks; classifier and extraction changes only.",
                  "current_file_sha256": code_hashes,
                  "ocr_source": str(cache.relative_to(ROOT)) if cache.is_relative_to(ROOT) else str(cache),
                  "engine": saved["engine"], "stats": stats, "results": rows})
    print(json.dumps(stats), flush=True)
    return int(require_correct and (stats["usable"] != len(ordinary) or stats["negative_detected"] != len(negatives) or stats["invalid_boxes"]))


def report(cases, result_file):
    results = json.loads(result_file.read_text("utf-8"))
    rows = {row["id"]: row for row in results["results"]}
    stats = results["stats"]
    def failed(row):
        return not row["valid_boxes"] or (not row["needs_review"] if row["expected_review"] else row["needs_review"] or row["expected"] != row["after"])
    report_lines = ["# 문서 종류 확장 실제 OCR 검증", "",
                    "24개 직접 작성한 가상 문서 문안 × 8조건 = 192장입니다. 합성 변형이며 실제 현장 사진 192장이 아닙니다.",
                    "조건: 원본, 5도 기울기, 책상 배경, 그림자, 흐림, 제목 잘림, 90도 회전, 판독 불가 저해상도.",
                    "Tesseract를 실제 실행해 저장한 동일 OCR 블록을 이전/현재 분류기에 전달했습니다. OCR 엔진 자체의 향상을 측정하는 비교가 아닙니다.",
                    f"이전 코드: `{results['baseline']}`. 엔진: `{results['engine']}`. API/LLM 호출 없음.", "",
                    f"- 일반 사진 분류: {stats['before_correct']}/{stats['ordinary']} → {stats['after_correct']}/{stats['ordinary']}",
                    f"- 분류 일치 + 재촬영 불필요: {stats['usable']}/{stats['ordinary']}",
                    f"- 분류 일치 + 하나 이상 항목 추출: {stats['with_fields']}/{stats['ordinary']} (값 전체의 정확도 지표는 아님)",
                    f"- 문서당 2개 지정 항목값 표본 확인: {stats['field_values_correct']}/{stats['field_values_checked']} (공백·문장부호 제거 후 비교, 전체 항목 정확도는 아님)",
                    f"- 판독 불가 사진 재촬영 처리: {stats['negative_detected']}/{stats['negatives']}",
                    f"- 좌표 범위 오류: {stats['invalid_boxes']}", "",
                    "|종류|일반 사진|이전 분류|현재 분류|재촬영 없이 진행|", "|---|---:|---:|---:|---:|"]
    for kind in sorted({row["expected"] for row in rows.values()}):
        group = [r for r in rows.values() if r["expected"] == kind and not r["expected_review"]]
        report_lines.append(f"|{doc_reader.RULES[kind]['label']} ({kind})|{len(group)}|{sum(r['before']==kind for r in group)}|{sum(r['after']==kind for r in group)}|{sum(r['after']==kind and not r['needs_review'] for r in group)}|")
    report_lines += ["", "## 분류·재촬영·좌표 실패", ""]
    failures = [r for r in rows.values() if failed(r)]
    report_lines += [f"- [{r['id']}](images/{r['id']}.jpg): 예상 {r['expected']}, 판정 {r['after']}, 재촬영 {r['needs_review']}" for r in failures] or ["없음. 이 고정된 합성 표본 안에서의 결과입니다."]
    report_lines += ["", "## 지정 항목값 불일치", ""]
    field_failures = [r for r in rows.values() if not r["expected_review"] and not all(r["field_checks"].values())]
    report_lines += [f"- [{r['id']}](images/{r['id']}.jpg): {', '.join(k for k, ok in r['field_checks'].items() if not ok)}" for r in field_failures] or ["없음."]
    report_lines += ["", "## 재현", "", "저장소 루트에서:", "```powershell",
                    "backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py generate",
                    "backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py ocr",
                    "backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py evaluate",
                    "backend/.venv/Scripts/python.exe backend/tests/expanded_document_samples.py report", "```", "",
                    "manifest.json은 이미지 해시/기대 종류/문안/조건을, ocr.json은 실제 인식 글자·좌표·신뢰도·엔진 정보를 저장합니다.",
                    "results.json은 같은 OCR 결과에 대한 전후 분류와 항목 추출값입니다. index.html에서 조건별 사진과 결과를 비교할 수 있습니다.",
                    "문안과 변형을 구현 중 사용한 개발 표본이며 독립 외부 평가가 아닙니다. 손글씨, 심한 가림, 모든 서식·촬영 장치를 검증하지 않았습니다."]
    (DEST / "README.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    cards = []
    for case in cases:
        if case["id"] not in rows:
            continue
        row = rows[case["id"]]
        label = doc_reader.RULES[case['expected']]['label']
        profile_label = PROFILE_LABELS[case['profile']]
        content = f"{case['expected']} {case['profile']} {case['id']} {label} {profile_label}"
        field_error = not row["expected_review"] and not all(row["field_checks"].values())
        check_text = "판독 불가 표본: 항목값 평가 제외" if row["expected_review"] else f"지정 항목값 {sum(row['field_checks'].values())}/{len(row['field_checks'])} 일치"
        cards.append(f'<article data-search="{html.escape(content)}" data-failed="{str(failed(row) or field_error).lower()}"><h2>{html.escape(label)} · {profile_label}</h2><p>{html.escape(case["id"])}</p><a href="{case["image"]}"><img loading="lazy" src="{case["image"]}" alt="{html.escape(case["id"])}"></a><p>예상 {case["expected"]} · 이전 {row["before"]} → 현재 {row["after"]} · 재촬영 {row["needs_review"]}</p><p>{check_text}</p><details><summary>원본 문안</summary><pre>{html.escape(case["reference"])}</pre></details><details><summary>실제 OCR / 추출 항목</summary><pre>{html.escape(row["text"])}</pre><pre>{html.escape(json.dumps(row["fields"],ensure_ascii=False,indent=2))}</pre></details></article>')
    page = '<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>문서 종류 확장 OCR 표본</title><style>body{font:16px system-ui;margin:24px;background:#f1f4f7;color:#172534}header{position:sticky;top:0;background:white;padding:16px;z-index:1}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px;margin-top:20px}article{background:white;padding:16px;border-radius:8px;min-width:0}h2{font-size:16px}img{width:100%;height:280px;object-fit:contain}pre{white-space:pre-wrap;overflow-wrap:anywhere}input{padding:10px;margin-right:12px}</style><header><h1>문서 종류 확장 실제 OCR</h1><p>24개 가상 문안 × 8조건. 합성 변형이며 현장 사진이 아닙니다. 같은 실제 OCR 결과의 전후 분류를 비교합니다.</p><input id="search" placeholder="종류·조건 검색"><label><input type="checkbox" id="failed">실패만 보기</label> <span id="count"></span> · <a href="README.md">검증 보고서</a> · <a href="../index.html">이전 표본</a></header><main>' + ''.join(cards) + '</main><script>const q=document.querySelector("#search"),f=document.querySelector("#failed"),cards=[...document.querySelectorAll("article")];function filter(){let n=0;for(const c of cards){const ok=c.dataset.search.includes(q.value.toLowerCase())&&(!f.checked||c.dataset.failed==="true");c.hidden=!ok;if(ok)n++;}document.querySelector("#count").textContent=n+" / "+cards.length+"장";}q.oninput=f.onchange=filter;filter();</script></html>'
    (DEST / "index.html").write_text(page, encoding="utf-8")
    print(f"Saved report and gallery; failures={len(failures)}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("generate", "ocr", "evaluate", "report"))
    parser.add_argument("--profiles", nargs="+", choices=PROFILES)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--cache", type=Path, default=DEST / "ocr.json")
    parser.add_argument("--output", type=Path, default=DEST / "results.json")
    parser.add_argument("--baseline-ref", default=BASELINE)
    parser.add_argument("--require-correct", action="store_true")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("workers must be positive")
    if args.command == "generate":
        generate()
        return 0
    cases = json.loads((DEST / "manifest.json").read_text("utf-8"))["cases"]
    if args.profiles:
        cases = [c for c in cases if c["profile"] in args.profiles]
    if args.command == "ocr":
        run_ocr(cases, args.workers, args.cache)
    elif args.command == "evaluate":
        return evaluate(cases, args.cache, args.output, args.baseline_ref, args.require_correct)
    else:
        report(cases, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())

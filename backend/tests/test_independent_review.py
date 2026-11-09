"""Independent offline regressions from review of reading and judgement workflows.

Every input is fabricated; these checks do not call OCR, external AI, or network
services. Assertions cover the values spoken/compared, not only classification.
"""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType, RecognizedDocument
from app.services import doc_reader, judge, llm
from app.services.judge import extract, facts, parse
from document_corpus import blocks


def read_offline(text, kind=None):
    lines = blocks([text])
    with patch.object(llm, "available", return_value=False):
        detected, _, fields, _ = doc_reader.read(lines)
    return RecognizedDocument(
        doc_type=kind or detected, blocks=lines, full_text=text, fields=fields
    )


class SourceEvidenceTest(unittest.TestCase):
    def test_two_amounts_in_one_row_do_not_make_them_interchangeable(self):
        lines = blocks(["근로계약서\n시급: 5000원 식비: 15000원"])
        with patch.object(llm, "ask_json", return_value={"doc_type": "contract", "fields": {"임금": "15000원"}}):
            with self.assertRaises(llm.LlmError):
                doc_reader._read_with_ai("\n".join(b.text for b in lines), lines, DocType.CONTRACT)

    def test_ai_changed_wage_cannot_remove_ocr_warning(self):
        text = (
            "근로계약서\n시급: 5000원\n소정근로시간: 1일 8시간\n근무일: 주5일\n"
            "계약기간: 2026년 1월 1일부터 2026년 12월 31일까지"
        )
        lines = blocks([text])
        fabricated = {
            "doc_type": "contract",
            "fields": {
                "임금": "15000원",
                "근로 시간": "1일 8시간",
                "계약 기간": "2026년 1월 1일부터 2026년 12월 31일까지",
            },
        }
        with patch.object(llm, "available", return_value=True), patch.object(
            llm, "ask_json", return_value=fabricated
        ):
            kind, _, fields, _ = doc_reader.read(lines)
        self.assertEqual("5000원", {f.label: f.value for f in fields}.get("임금"))
        document = RecognizedDocument(doc_type=kind, blocks=lines, fields=fields, full_text=text)
        findings = judge.run(document)["findings"]
        self.assertTrue(any(f["rule_id"] == "LAB-003" and f["level"] == "caution" for f in findings))

    def test_ai_cannot_substitute_an_amount_from_another_field(self):
        text = (
            "근로계약서\n시급: 5000원\n식비: 15000원\n소정근로시간: 1일 8시간\n"
            "근무일: 주5일\n계약기간: 2026년 1월 1일부터 2026년 12월 31일까지"
        )
        lines = blocks([text])
        answer = {"doc_type": "contract", "fields": {
            "임금": "15000원", "근로 시간": "1일 8시간",
            "계약 기간": "2026년 1월 1일부터 2026년 12월 31일까지",
        }}
        with patch.object(llm, "available", return_value=True), patch.object(llm, "ask_json", return_value=answer):
            kind, _, fields, _ = doc_reader.read(lines)
        self.assertEqual("5000원", {f.label: f.value for f in fields}.get("임금"))
        document = RecognizedDocument(doc_type=kind, blocks=lines, fields=fields, full_text=text)
        self.assertTrue(any(f["rule_id"] == "LAB-003" for f in judge.run(document)["findings"]))

    def test_ai_cannot_invent_a_missing_place(self):
        lines = blocks(["가정통신문\n일시: 11월 3일\n장소:"])
        answer = {"doc_type": "notice", "fields": {"날짜": "11월 3일", "장소": "서울대공원"}}
        with patch.object(llm, "available", return_value=True), patch.object(llm, "ask_json", return_value=answer):
            kind, _, fields, _ = doc_reader.read(lines)
        self.assertNotIn("서울대공원", doc_reader.build_speech(kind, fields, lines))
        self.assertNotIn("장소", {f.label for f in fields})


class MoneyMagnitudeTest(unittest.TestCase):
    def test_mixed_korean_units_preserve_the_entire_amount(self):
        for text, expected in (
            ("5천만원", 50_000_000),
            ("1억5천만원", 150_000_000),
            ("2억 5천만원", 250_000_000),
            ("1.5만원", 15_000),
            ("1만 2천원", 12_000),
            ("1억 5만원", 100_050_000),
            ("오천만원", 50_000_000),
            ("10,320원", 10_320),
        ):
            with self.subTest(text=text):
                self.assertEqual(expected, parse.parse_money(text))

    def test_lease_deposit_and_rent_remain_separate_correct_amounts(self):
        document = read_offline(
            "주택 임대차 계약서\n임대인 김예시 임차인 이가상\n"
            "보증금 1억5천만원 월세 50만원\n임대차기간 2년"
        )
        values = extract.extract(document)
        self.assertEqual(150_000_000, values["deposit"]["value"])
        self.assertEqual(500_000, values["monthly_rent"]["value"])


class WorkingScheduleTest(unittest.TestCase):
    def test_monthly_conversion_respects_explicit_weekly_work(self):
        # The engine's own documented conversion yields about 12,786/hour for
        # 24 weekly hours. Substituting 40 hours creates a false low-wage warning.
        self.assertGreater(facts.hourly_from_monthly(1_600_000, 24), 10_320)
        for schedule in ("소정근로시간: 1일 8시간\n근무일: 주3일", "소정근로시간: 주24시간"):
            with self.subTest(schedule=schedule):
                document = read_offline(
                    "근로계약서\n근로자: 김예시\n월급: 160만원\n" + schedule +
                    "\n계약기간: 2026년 1월 1일부터 2026년 12월 31일까지"
                )
                self.assertEqual(24, extract.extract(document)["weekly_hours"]["value"])
                warnings = [f for f in judge.run(document)["findings"] if f["rule_id"] == "LAB-003"]
                self.assertEqual([], warnings)


class FormValueAssociationTest(unittest.TestCase):
    def test_receipt_refund_is_not_the_payment_amount(self):
        for amount_lines in (
            "환불 금액: 0원\n결제 금액: 10000원",
            "할인 금액: 1000원\n결제 금액: 10000원",
        ):
            with self.subTest(lines=amount_lines):
                document = read_offline("영수증\n" + amount_lines + "\n거래일: 2026년 11월 9일\n상호: 문구점")
                self.assertEqual(DocType.RECEIPT, document.doc_type)
                self.assertEqual("10000원", {f.label: f.value for f in document.fields}.get("결제 금액"))

    def test_refund_only_receipt_does_not_invent_a_payment_amount(self):
        document = read_offline("영수증\n환불 금액: 5000원\n거래일: 2026년 11월 9일\n상호: 문구점")
        self.assertNotIn("결제 금액", {f.label for f in document.fields})

    def test_blank_invoice_amount_cannot_borrow_customer_identifier(self):
        document = read_offline(
            "청구서\n청구 금액:\n고객 번호: 123456\n납부 기한: 2026년 11월 30일\n납부 방법: 계좌이체"
        )
        self.assertNotIn("청구 금액", {f.label for f in document.fields})
        unread = next(f for f in judge.run(document)["findings"] if f["rule_id"].endswith("_unread"))
        self.assertIn("청구 금액", unread["speech"])

    def test_plain_next_line_value_is_still_read(self):
        document = read_offline("청구서\n청구 금액:\n85000원\n납부 기한: 2026년 11월 30일")
        self.assertEqual("85000원", {f.label: f.value for f in document.fields}.get("청구 금액"))


if __name__ == "__main__":
    unittest.main()

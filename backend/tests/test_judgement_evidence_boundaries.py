"""Reading and judgement may not borrow another cell or an attached example."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType, RecognizedDocument
from app.services import doc_reader, judge, llm
from app.services.judge.extract import extract
from document_corpus import blocks


def document(pages, kind="contract"):
    lines = blocks(pages)
    fields = doc_reader._extract_by_rules(lines, DocType(kind))
    return RecognizedDocument(doc_type=kind, blocks=lines, fields=fields,
                              full_text="\n".join(line.text for line in lines))


class JudgementEvidenceBoundaryTest(unittest.TestCase):
    def test_blank_wage_does_not_borrow_transport_allowance(self):
        for tail in ("시급:\n교통비: 5000원", "시급: 교통비: 5000원", "시급:\n교통비 5000원"):
            with self.subTest(tail=tail):
                doc = document(["근로계약서\n근로자: 김예시\n" + tail])
                self.assertNotIn("hourly_wage", extract(doc))
                self.assertNotIn("LAB-003", {f["rule_id"] for f in judge.run(doc)["findings"]})

    def test_blank_deposit_does_not_borrow_monthly_rent(self):
        for tail in ("보증금:\n월세: 50만원", "보증금: 월세: 50만원", "보증금 월세 50만원"):
            with self.subTest(tail=tail):
                values = extract(document(["주택 임대차 계약서\n" + tail]))
                self.assertNotIn("deposit", values)
                self.assertEqual(500000, values["monthly_rent"]["value"])

    def test_unlabeled_number_on_another_page_is_not_a_wrapped_wage(self):
        values = extract(document(["근로계약서\n근로자: 김예시\n시급:", "5000원"]))
        self.assertNotIn("hourly_wage", values)

    def test_same_page_wrapped_amount_remains_supported(self):
        values = extract(document(["근로계약서\n근로자: 김예시\n시급:\n12000원"]))
        self.assertEqual(12000, values["hourly_wage"]["value"])

    def test_payday_is_not_a_wage(self):
        values = extract(document(["근로계약서\n근로자: 김예시\n임금 지급일: 매월 25일"]))
        self.assertNotIn("hourly_wage", values)
        self.assertNotIn("monthly_wage", values)

    def test_guide_cannot_supply_missing_field_values(self):
        doc = document(["근로계약서\n근로자: 김예시\n시급:", "근로계약서 작성 가이드\n시급: 5000원"])
        self.assertNotIn("임금", {f.label for f in doc.fields})
        self.assertNotIn("LAB-003", {f["rule_id"] for f in judge.run(doc)["findings"]})
        self.assertIn("시급: 5000원", doc.full_text)  # Original remains available to read.
        self.assertEqual("시급: 5000원", doc.blocks[-1].text)

    def test_guide_clauses_do_not_become_signed_contract_terms(self):
        main = "근로계약서\n근로자: 김예시\n시급: 12000원"
        guide = "근로계약서 작성 가이드\n퇴사 시 위약금 100만원을 배상한다."
        result = judge.run(document([main, guide]))
        self.assertNotIn("LAB-004", {f["rule_id"] for f in result["findings"]})

    def test_real_continuation_after_a_guide_keeps_original_evidence_index(self):
        doc = document(["근로계약서\n근로자: 김예시", "근로계약서 작성 가이드\n시급: 5000원", "시급: 8000원"])
        finding = next(f for f in judge.run(doc)["findings"] if f["rule_id"] == "LAB-003")
        self.assertEqual(len(doc.blocks) - 1, finding["line"])
        self.assertEqual("시급: 8000원", finding["evidence"])

    def test_ai_prompt_and_validation_exclude_example_values(self):
        doc = document(["근로계약서\n근로자: 김예시\n시급:", "근로계약서 작성 가이드\n시급: 5000원"])
        with patch.object(llm, "ask_json", return_value={"doc_type": "contract", "fields": {"임금": "5000원"}}) as ask:
            with self.assertRaises(llm.LlmError):
                doc_reader._read_with_ai(doc.full_text, doc.blocks, DocType.CONTRACT)
        self.assertNotIn("5000원", ask.call_args.args[0])

    def test_reading_only_form_guide_does_not_complete_missing_fields(self):
        doc = document(["영수증\n상호: 가상상점", "영수증 작성 가이드\n결제 금액: 5000원"], "receipt")
        self.assertFalse(any(f.label == "금액" for f in doc.fields))
        self.assertTrue(any(f["rule_id"] == "form_receipt_unread" for f in judge.run(doc)["findings"]))

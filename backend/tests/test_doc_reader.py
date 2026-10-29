"""Run offline: python -m unittest discover -s backend/tests -p "test_*.py"."""

import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType, RecognizedDocument
from app.routers.read import read_document
from app.services import doc_reader, judge, llm, ocr
from document_corpus import blocks, cases, variants
from fastapi import HTTPException, UploadFile
from app.routers.judge import JudgeRequest, judge_document


class DocumentCorpusTest(unittest.TestCase):
    def test_classification_corpus_and_ocr_variants(self):
        with patch.object(llm, "available", return_value=False):
            for name, expected, lines, source in cases():
                for variant, sample in variants(lines):
                    with self.subTest(case=name, source=source, variant=variant):
                        actual, _, _, reader = doc_reader.read(sample)
                        self.assertEqual(expected, actual.value)
                        self.assertEqual("rules", reader)

    def test_duplicate_pages_do_not_inflate_evidence(self):
        for name, _, lines, _ in cases():
            with self.subTest(case=name):
                repeated = dict(variants(lines))["repeated_pages"]
                self.assertEqual(doc_reader.CLASSIFIER.classify(lines).scores,
                                 doc_reader.CLASSIFIER.classify(repeated).scores)

    def test_no_arbitrary_winner_without_title(self):
        sample = blocks(["근로자 임금 소정근로시간\n학부모 일시 장소"])
        result = doc_reader.CLASSIFIER.classify(sample)
        self.assertEqual(DocType.UNKNOWN, result.doc_type)
        self.assertEqual("ambiguous_evidence", result.reason)

    def test_title_only_with_parenthetical_and_unicode_noise(self):
        for variant, sample in variants(blocks(["근로계약서 (예시)"])):
            with self.subTest(variant=variant):
                self.assertEqual(DocType.CONTRACT, doc_reader.CLASSIFIER.classify(sample).doc_type)

    def test_short_consent_footer_does_not_change_contract(self):
        main = "주택 임대차 계약서\n임대인 임차인\n보증금 5000만원\n임대차기간 2년"
        for repetitions in (1, 10, 100):
            with self.subTest(repetitions=repetitions):
                text = main + "\n" + "개인정보 수집 이용에 동의합니다.\n" * repetitions
                self.assertEqual(DocType.CONTRACT, doc_reader.CLASSIFIER.classify(blocks([text])).doc_type)

    def test_cover_does_not_hide_conflicting_contract_families(self):
        sample = blocks(["제출 표지\n접수번호 123",
                         "근로계약서\n근로자 사업주\n임금 200만원\n근로시간 8시간",
                         "임대차계약서\n임대인 임차인\n보증금 300만원\n임대차기간 2년"])
        result = doc_reader.CLASSIFIER.classify(sample)
        self.assertEqual(DocType.UNKNOWN, result.doc_type)
        self.assertEqual("conflicting_documents", result.reason)


class ReaderFallbackTest(unittest.TestCase):
    def setUp(self):
        self.lines = blocks(["가정통신문\n일시: 11월 3일\n장소: 박물관"])

    def test_ai_cannot_replace_evidenced_type(self):
        with patch.object(llm, "available", return_value=True), patch.object(
            llm, "ask_json", return_value={"doc_type": "consent", "fields": {"수집 목적": "행사"}}
        ):
            kind, _, fields, reader = doc_reader.read(self.lines)
        self.assertEqual(DocType.NOTICE, kind)
        self.assertEqual("rules", reader)
        self.assertEqual({"날짜": "11월 3일", "장소": "박물관"}, {f.label: f.value for f in fields})

    def test_unknown_does_not_make_ai_call(self):
        with patch.object(llm, "available", return_value=True), patch.object(llm, "ask_json") as ask:
            kind, _, fields, reader = doc_reader.read(blocks(["동의 동의 동의"]))
        self.assertEqual((DocType.UNKNOWN, [], "rules"), (kind, fields, reader))
        ask.assert_not_called()

    def test_ai_valid_values_keep_original_line_indices(self):
        with patch.object(llm, "available", return_value=True), patch.object(
            llm, "ask_json", return_value={"doc_type": "notice", "fields": {"날짜": "11월 3일", "장소": "박물관"}}
        ) as ask:
            kind, _, fields, reader = doc_reader.read(self.lines)
        self.assertEqual((DocType.NOTICE, "ai"), (kind, reader))
        self.assertEqual([1, 2], [f.line for f in fields])
        self.assertIn('"notice"', ask.call_args.args[0])

    def test_malformed_ai_responses_fall_back(self):
        for answer in ([], None, "notice", {"doc_type": []},
                       {"doc_type": "notice", "fields": ["not an object"]},
                       {"doc_type": "notice", "fields": {"날짜": 123}}):
            with self.subTest(answer=answer), patch.object(llm, "available", return_value=True), patch.object(
                llm, "ask_json", return_value=answer
            ):
                kind, _, fields, reader = doc_reader.read(self.lines)
                self.assertEqual((DocType.NOTICE, "rules"), (kind, reader))
                self.assertEqual(2, len(fields))

    def test_network_failure_falls_back(self):
        with patch.object(llm, "available", return_value=True), patch.object(
            llm, "ask_json", side_effect=llm.LlmError("offline")
        ):
            kind, _, fields, reader = doc_reader.read(self.lines)
        self.assertEqual((DocType.NOTICE, 2, "rules"), (kind, len(fields), reader))

    def test_empty_and_ambiguous_speech_is_actionable(self):
        self.assertIn("다시 찍어", doc_reader.build_speech(DocType.UNKNOWN, [], []))
        self.assertIn("알아내지 못했어요", doc_reader.build_speech(DocType.UNKNOWN, [], self.lines))

    def test_new_contract_kinds_reach_judge(self):
        examples = {
            "lease_housing": "주택 임대차 계약서\n주택 전세 보증금 5000만원\n임대차기간 2년",
            "loan_private": "차용증\n채권자 채무자\n차용금 100만원\n변제기 2027년 1월",
            "consumer_membership": "헬스장 이용계약서\n회원권 이용료 30만원\n중도해지 환불 조건",
        }
        with patch.object(llm, "available", return_value=False):
            for expected, text in examples.items():
                with self.subTest(subtype=expected):
                    lines = blocks([text])
                    kind, _, fields, _ = doc_reader.read(lines)
                    doc = RecognizedDocument(doc_type=kind, blocks=lines, full_text=text, fields=fields)
                    self.assertEqual(expected, judge.run(doc)["subtype"])


class ReadRouteTest(unittest.IsolatedAsyncioTestCase):
    async def test_partial_page_warns_and_skips_field_ai_and_judgement(self):
        first = blocks(["근로계약서\n임금: 300만원"])
        uploads = [UploadFile(file=io.BytesIO(b"image")) for _ in range(2)]
        with patch.object(llm, "ask_json") as ask, patch.object(ocr, "recognize", side_effect=[
            ocr.OcrResult(first, 800, 1000), ocr.OcrResult(first[:1], 800, 1000, needs_review=True)
        ]):
            result = await read_document(uploads)
        self.assertTrue(result.needs_review)
        self.assertEqual([1], result.review_pages)
        self.assertEqual([], result.fields)
        self.assertIn("2페이지", result.speech)
        self.assertIn("다시 찍어", result.speech)
        ask.assert_not_called()
        with self.assertRaises(HTTPException) as error:
            await judge_document(JudgeRequest(**result.model_dump()))
        self.assertEqual(422, error.exception.status_code)
        for upload in uploads:
            await upload.close()

    async def test_empty_upload_list_is_actionable(self):
        with self.assertRaises(HTTPException) as error:
            await read_document([])
        self.assertEqual(400, error.exception.status_code)

    async def test_multipage_route_keeps_boxes_and_classifies_main_form(self):
        first = blocks(["가정통신문\n일시: 내일\n장소: 박물관\n준비물: 물"])
        appendix = blocks(["개인정보 수집 이용 동의서\n수집 목적: 행사\n수집 항목: 성명\n보유 기간: 1년"])
        uploads = [UploadFile(file=io.BytesIO(b"fake image"), filename=f"{i}.png") for i in range(2)]
        with patch.object(llm, "available", return_value=False), patch.object(
            ocr, "recognize", side_effect=[ocr.OcrResult(first, 800, 1000), ocr.OcrResult(appendix, 900, 1100)]
        ):
            result = await read_document(uploads)
        self.assertEqual(DocType.NOTICE, result.doc_type)
        self.assertEqual([0] * len(first) + [1] * len(appendix), [b.page for b in result.blocks])
        self.assertEqual(first[0].box, result.blocks[0].box)
        self.assertEqual([800, 900], [p.width for p in result.pages])
        self.assertIn("2페이지짜리", result.speech)
        self.assertEqual(result, RecognizedDocument.model_validate_json(result.model_dump_json()))
        for upload in uploads:
            await upload.close()


if __name__ == "__main__":
    unittest.main()

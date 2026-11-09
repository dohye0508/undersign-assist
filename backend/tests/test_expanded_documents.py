"""Independent text/routing checks; actual OCR is in expanded_document_samples.py."""
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import HTTPException, UploadFile
from api_fixtures import image_bytes
from app.models import DocType, Field, RecognizedDocument
from app.routers.read import read_document
from app.routers.judge import JudgeRequest, judge_document
from app.services import doc_reader, judge, llm, ocr
from document_corpus import blocks, variants

# Authored independently of the saved image corpus.
EXAMPLES = {
    "authorization": "위임장\n위임인: 김예시\n수임인: 이가상\n위임 사항: 주민등록 서류 수령\n위임 기간: 2026년 11월 9일\n위임인 서명: 김예시",
    "certificate": "재직증명서\n성명: 김예시\n소속: 가상회사\n재직 기간: 2024년 3월부터 현재\n발급일: 2026년 11월 9일\n발급기관: 가상회사\n위 사실을 증명합니다.",
    "invoice": "관리비 납부 고지서\n납부자: 김예시\n청구 금액: 85000원\n납부 기한: 2026년 11월 30일\n납부 계좌: 예시은행 000-000\n청구 내역: 공용 전기료와 청소비\n청구 기관: 가상관리소",
    "receipt": "물품 구매 영수증\n상호: 가상문구점\n거래 일시: 2026년 11월 9일\n품목: 공책\n결제 금액: 10000원\n결제 수단: 카드\n승인 번호: 123456\n결제 완료",
    "pledge": "보안 서약서\n서약자: 김예시\n서약 내용: 업무 중 알게 된 자료를 외부에 제공하지 않습니다.\n준수 사항: 자료를 안전하게 보관합니다.\n위반 시 조치: 기관의 안내에 따릅니다.\n서약일: 2026년 11월 9일\n서약자 서명: 김예시",
    "report": "현장 조사 보고서\n보고자: 김예시\n보고일: 2026년 11월 9일\n조사 목적: 시설 이용 현황 확인\n조사 내용: 안내판과 출입구 점검\n조사 결과: 안내판 교체 필요\n향후 계획: 다음 달 재점검",
    "questionnaire": "도서관 이용 만족도 설문지\n조사 목적: 이용 환경 개선\n응답자: 가상 이용자\n문항 1: 도서관 시설에 만족하십니까?\n매우 만족 보통 불만족\n문항 2: 다시 이용할 의향이 있습니까?\n예 아니오\n기타 의견: 좌석을 늘려 주세요.",
    "activity_consent": "현장체험학습 참가 동의서\n활동명: 역사 박물관 견학\n참가자: 김예시\n보호자: 이가상\n활동 일시: 2026년 11월 20일\n활동 장소: 가상박물관\n참가에 동의합니다.\n보호자 서명: 이가상",
}
PRIVACY = "개인정보 수집 이용 동의서\n수집 목적: 접수 확인\n수집 항목: 성명 연락처\n보유 기간: 1개월\n동의를 거부할 수 있습니다."


class ExpandedClassificationTest(unittest.TestCase):
    def test_new_types_survive_spacing_unicode_and_repeated_pages(self):
        for kind, text in EXAMPLES.items():
            for variant, lines in variants(blocks([text])):
                with self.subTest(kind=kind, variant=variant):
                    self.assertEqual(kind, doc_reader.CLASSIFIER.classify(lines).doc_type.value)

    def test_cropped_title_uses_independent_body_evidence(self):
        for kind, text in EXAMPLES.items():
            with self.subTest(kind=kind):
                self.assertEqual(kind, doc_reader.CLASSIFIER.classify(blocks([text.split("\n", 1)[1]])).doc_type.value)

    def test_privacy_appendix_does_not_replace_main_form(self):
        for kind in ("authorization", "certificate", "pledge", "report", "questionnaire", "activity_consent"):
            with self.subTest(kind=kind):
                self.assertEqual(kind, doc_reader.CLASSIFIER.classify(blocks([EXAMPLES[kind], PRIVACY])).doc_type.value)

    def test_unrelated_forms_on_separate_pages_abstain(self):
        for first, second in (("authorization", "receipt"), ("report", "invoice"),
                              ("certificate", "questionnaire"), ("invoice", "pledge")):
            with self.subTest(first=first, second=second):
                result = doc_reader.CLASSIFIER.classify(blocks([EXAMPLES[first], EXAMPLES[second]]))
                self.assertEqual(DocType.UNKNOWN, result.doc_type)
                self.assertEqual("conflicting_documents", result.reason)

    def test_reference_lists_and_instructions_are_not_forms(self):
        for kind, text in EXAMPLES.items():
            title = text.splitlines()[0]
            for reference in (title + " 작성 가이드\n" + text.split("\n", 1)[1],
                              "제출 서류 목록\n" + title, "제출 서류: " + title,
                              "내일까지 " + title + "를 제출해 주세요."):
                with self.subTest(kind=kind, reference=reference):
                    self.assertEqual(DocType.UNKNOWN, doc_reader.CLASSIFIER.classify(blocks([reference])).doc_type)

    def test_generic_and_medical_consent_are_not_activity_consent(self):
        for text in ("동의서\n성명: 김예시\n동의함 동의하지 않음",
                     "수술 동의서\n수술명: 시험용\n환자: 김예시\n보호자: 이가상\n수술에 동의합니다.",
                     "검사 및 시술 동의서\n시술명: 시험용\n환자 성명: 김예시\n보호자 서명: 이가상"):
            self.assertEqual(DocType.UNKNOWN, doc_reader.CLASSIFIER.classify(blocks([text])).doc_type)
        self.assertEqual(DocType.CONSENT, doc_reader.CLASSIFIER.classify(blocks([PRIVACY])).doc_type)

    def test_certificate_request_is_application_and_quote_is_not_invoice(self):
        request = "재직증명서 발급 신청서\n신청인: 김예시\n성명: 김예시\n소속: 가상회사\n연락처: 010-0000-0000\n신청 내용: 증명서 1부"
        self.assertEqual(DocType.APPLICATION, doc_reader.CLASSIFIER.classify(blocks([request])).doc_type)
        quote = "공사 견적서\n예상 금액: 300만원\n작업 기간: 7일\n견적 유효기간: 한 달\n의뢰인: 예시회사"
        self.assertEqual(DocType.UNKNOWN, doc_reader.CLASSIFIER.classify(blocks([quote])).doc_type)

    def test_document_mentions_do_not_override_main_title(self):
        for kind, text in EXAMPLES.items():
            with self.subTest(kind=kind):
                lines = blocks([text + "\n제출 서류: 개인정보 동의서 및 참가 신청서\n첨부 서류: 위임장과 영수증"])
                self.assertEqual(kind, doc_reader.CLASSIFIER.classify(lines).doc_type.value)

    def test_payment_related_body_does_not_override_document_purpose(self):
        invoice = EXAMPLES["invoice"] + "\n전월 결제 완료\n전월 카드 승인번호: 123456"
        receipt = EXAMPLES["receipt"] + "\n이전 청구 금액: 10000원\n이전 납부 기한: 2026년 11월 9일"
        self.assertEqual(DocType("invoice"), doc_reader.CLASSIFIER.classify(blocks([invoice])).doc_type)
        self.assertEqual(DocType("receipt"), doc_reader.CLASSIFIER.classify(blocks([receipt])).doc_type)

    def test_repeated_generic_terms_do_not_create_supported_form(self):
        for text in ("보호자 연락처 동의함 " * 100, "청구 금액 " * 100,
                     "작성자 결과 " * 100, "문항 매우만족 " * 100):
            self.assertEqual(DocType.UNKNOWN, doc_reader.CLASSIFIER.classify(blocks([text])).doc_type)

    def test_privacy_only_under_activity_heading_uses_privacy_rules(self):
        text = "체험학습 참가 동의서\n" + PRIVACY.split("\n", 1)[1]
        self.assertEqual(DocType.CONSENT, doc_reader.CLASSIFIER.classify(blocks([text])).doc_type)

    def test_medical_activity_title_cannot_fall_back_to_general_participation(self):
        for title in ("임상시험 참가 동의서", "검사 활동 동의서"):
            text = title + "\n활동명: 임상시험\n참가자: 홍가상\n활동 일시: 내일\n시험 참가에 동의합니다."
            result = doc_reader.CLASSIFIER.classify(blocks([text]))
            self.assertEqual(DocType.UNKNOWN, result.doc_type)
            self.assertEqual("unsupported_document", result.reason)

    def test_payment_method_guide_is_not_invoice(self):
        text = "납부 방법 안내\n청구 금액: 30000원\n납부 기한: 내일\n청구 기관: 예시기관"
        result = doc_reader.CLASSIFIER.classify(blocks([text]))
        self.assertEqual(DocType.UNKNOWN, result.doc_type)
        self.assertEqual("reference_material", result.reason)


class ExpandedReaderTest(unittest.IsolatedAsyncioTestCase):
    async def test_route_serializes_all_new_types_with_fields_and_speech(self):
        for kind, text in EXAMPLES.items():
            with self.subTest(kind=kind):
                lines = blocks([text])
                upload = UploadFile(file=io.BytesIO(image_bytes()), filename="form.jpg")
                with patch.object(llm, "available", return_value=False), patch.object(
                    ocr, "recognize", return_value=ocr.OcrResult(lines, 1000, 1000)
                ):
                    result = await read_document([upload])
                await upload.close()
                self.assertEqual(kind, result.doc_type.value)
                self.assertEqual(result, RecognizedDocument.model_validate_json(result.model_dump_json()))
                self.assertGreaterEqual(len(result.fields), 3)
                self.assertIn(result.doc_type_label, result.speech)
                for field in result.fields:
                    self.assertGreaterEqual(field.line, 0)
                    self.assertLess(field.line, len(lines))

    async def test_unreadable_new_form_cannot_reach_judgement(self):
        lines = blocks([EXAMPLES["authorization"]])
        upload = UploadFile(file=io.BytesIO(image_bytes()))
        with patch.object(llm, "ask_json") as ask, patch.object(
            ocr, "recognize", return_value=ocr.OcrResult(lines, 1000, 1000, needs_review=True)
        ):
            result = await read_document([upload])
        await upload.close()
        self.assertTrue(result.needs_review)
        self.assertEqual([], result.fields)
        ask.assert_not_called()
        with self.assertRaises(HTTPException) as error:
            await judge_document(JudgeRequest(**result.model_dump()))
        self.assertEqual(422, error.exception.status_code)

    def test_new_type_checks_do_not_run_legacy_legal_rules(self):
        for kind, text in EXAMPLES.items():
            with self.subTest(kind=kind):
                document = RecognizedDocument(doc_type=DocType(kind), blocks=blocks([text]), full_text=text)
                with patch.object(judge.E, "extract", side_effect=AssertionError("legacy legal extraction")):
                    result = judge.run(document)
                self.assertEqual(kind, result["subtype"])
                self.assertEqual([], result["questions"])
                self.assertTrue(result["findings"])
                self.assertTrue(all(f["level"] == "info" and not f["basis"] for f in result["findings"]))
                self.assertTrue(all(f["rule_id"].startswith("form_" + kind) for f in result["findings"]))

    def test_unread_field_checks_ignore_client_supplied_fields(self):
        document = RecognizedDocument(doc_type=DocType("authorization"), blocks=blocks(["위임장"]),
                                      fields=[Field(label="위임인", value="조작된 값", line=0)])
        result = judge.run(document)
        unread = next(f for f in result["findings"] if f["rule_id"].endswith("_unread"))
        self.assertIn("위임인", unread["speech"])

    def test_empty_field_cannot_borrow_text_from_next_page(self):
        lines = blocks(["위임장\n위임인:", "다음 페이지 설명문"])
        fields = doc_reader._extract_by_rules(lines, DocType("authorization"))
        self.assertNotIn("위임인", {field.label for field in fields})

    def test_specific_label_wins_over_its_short_prefix(self):
        receipt = blocks(["영수증\n거래 일시: 2026년 11월 9일\n결제 금액: 10000원"])
        actual = {f.label: f.value for f in doc_reader._extract_by_rules(receipt, DocType("receipt"))}
        self.assertEqual("2026년 11월 9일", actual["거래일"])
        consent = blocks(["참가 동의서\n참가자 성명: 김예시\n보호자 성명: 이가상"])
        actual = {f.label: f.value for f in doc_reader._extract_by_rules(consent, DocType("activity_consent"))}
        self.assertEqual("김예시", actual["참가자"])
        self.assertEqual("이가상", actual["보호자"])

    def test_report_heading_is_not_extracted_as_result_value(self):
        lines = blocks(["조사 결과 보고서\n보고자: 김예시\n조사 결과: 안내판 교체 필요"])
        fields = doc_reader._extract_by_rules(lines, DocType("report"))
        result = next(f for f in fields if f.label == "결과")
        self.assertEqual("안내판 교체 필요", result.value)
        self.assertEqual(2, result.line)

    def test_document_title_can_be_a_real_field_value_without_colon(self):
        for kind, text, label, expected in (
            ("authorization", "위임장\n위임 업무 재직증명서\n위임인 김예시\n대리인 이가상", "위임 업무", "재직증명서"),
            ("report", "현장 조사 보고서\n보고 대상 시설 점검 보고서\n보고자 김예시", "보고 대상", "시설 점검 보고서"),
        ):
            with self.subTest(kind=kind):
                fields = doc_reader._extract_by_rules(blocks([text]), DocType(kind))
                self.assertEqual(expected, {f.label: f.value for f in fields}.get(label))

    def test_signature_placeholders_do_not_count_as_read_names(self):
        text = "위임장\n위임인: (서명)\n대리인: (인)\n위임 업무: ____"
        document = RecognizedDocument(doc_type=DocType("authorization"), blocks=blocks([text]))
        unread = next(f for f in judge.run(document)["findings"] if f["rule_id"].endswith("_unread"))
        self.assertIn("위임인", unread["speech"])
        self.assertIn("대리인", unread["speech"])

    def test_each_new_type_extracts_its_own_meaningful_values(self):
        expected = {
            "authorization": {"위임인": "김예시", "대리인": "이가상", "위임 업무": "주민등록 서류 수령"},
            "certificate": {"성명": "김예시", "발급 기관": "가상회사", "확인 내용": "2024년 3월부터 현재"},
            "invoice": {"청구 금액": "85000원", "납부 기한": "2026년 11월 30일", "납부 방법": "예시은행 000-000"},
            "receipt": {"결제 금액": "10000원", "상호": "가상문구점", "승인 번호": "123456"},
            "pledge": {"서약자": "김예시", "서약 내용": "업무 중 알게 된 자료를 외부에 제공하지 않습니다"},
            "report": {"보고자": "김예시", "결과": "안내판 교체 필요", "향후 계획": "다음 달 재점검"},
            "questionnaire": {"조사 목적": "이용 환경 개선", "질문": "1: 도서관 시설에 만족하십니까?"},
            "activity_consent": {"참가자": "김예시", "보호자": "이가상", "장소": "가상박물관"},
        }
        for kind, values in expected.items():
            with self.subTest(kind=kind):
                fields = doc_reader._extract_by_rules(blocks([EXAMPLES[kind]]), DocType(kind))
                actual = {f.label: f.value for f in fields}
                self.assertEqual(values, {key: actual.get(key) for key in values})

    def test_same_type_keeps_document_specific_values(self):
        with patch.object(llm, "available", return_value=False):
            for kind, text in EXAMPLES.items():
                with self.subTest(kind=kind):
                    modified = text.replace("김예시", "박가상").replace("10000원", "22000원").replace("85000원", "99000원").replace("좌석을 늘려", "책을 늘려")
                    original = doc_reader.read(blocks([text]))
                    changed = doc_reader.read(blocks([modified]))
                    self.assertEqual(original[0], changed[0])
                    self.assertNotEqual([f.value for f in original[2]], [f.value for f in changed[2]])


if __name__ == "__main__":
    unittest.main()

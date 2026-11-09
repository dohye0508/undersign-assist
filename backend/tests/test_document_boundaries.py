"""Distinct synthetic page-boundary cases; no OCR, network, or private files."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.doc_classifier import DocumentClassifier
from document_corpus import blocks


AUTHORIZATION = "위임장\n위임인: 김한빛\n대리인: 이새봄\n위임 업무: 도서관 회원증 수령\n위임 기간: 11월 10일"
PRIVACY = "개인정보 수집 이용 동의서\n수집 목적: 서류 접수\n수집 항목: 성명 연락처\n보유 기간: 접수 후 한 달\n동의를 거부할 수 있습니다."
NOTICE = "가정통신문\n학부모님께 역사 체험학습을 안내합니다.\n일시: 11월 20일\n장소: 시립박물관\n준비물: 필기구"
ACTIVITY = "체험학습 참가 동의서\n활동명: 역사 체험학습\n참가자: 김한빛\n활동 일시: 11월 20일\n참가에 동의합니다."
APPLICATION = "공모전 참가신청서\n신청인: 김한빛\n성명: 김한빛\n소속: 예시학교\n연락처: 010-0000-0000\n참가 부문: 발명"
SUMMARY = "작품요약서\n작품명: 소리 나침반\n팀명: 새봄팀\n기획의도: 길 찾기 지원\n사용 기술: 음성 안내"
RECEIPT = "영수증\n상호: 예시문구\n품목: 공책\n결제 금액: 3000원\n거래일: 11월 10일\n결제 완료"
CLINICAL = "임상시험 참가 동의서\n참가자: 김한빛\n시험 내용: 시험용 예시\n시험일: 11월 20일\n담당 연구원: 이새봄"
CLINICAL_FIELDS = "임상시험 참가 동의서\n활동명: 시험용 임상시험\n참가자: 김한빛\n활동 일시: 11월 20일\n참가에 동의합니다."
COVER = "제출 서류 표지\n예시기관\n접수 번호: 456"
SPLIT_GUIDE = "청구서 작성\n가이드\n청구 금액: 50000원\n납부 기한: 11월 말\n청구 기관: 예시관리소"
SPLIT_POLICY = "개인정보 처리\n방침\n수집 목적: 회원 관리\n수집 항목: 성명 연락처\n보유 기간: 탈퇴까지\n별도 동의를 받습니다."

# This table intentionally varies the document relationship, not only spelling.
# The first three dictionaries also provide reusable image-generation inputs.
BOUNDARY_CASES = [
    {"id": "cover_lists_titles", "expected": "authorization", "pages": [
        "제출 서류 표지\n첨부 서류 목록\n위임장\n개인정보 수집 이용 동의서", AUTHORIZATION, PRIVACY]},
    {"id": "split_reference_appendix", "expected": "authorization", "pages": [AUTHORIZATION, SPLIT_GUIDE]},
    {"id": "unsupported_primary_with_privacy", "expected": "unknown", "pages": [CLINICAL, PRIVACY]},
    {"id": "blank_pages_around_receipt", "expected": "receipt", "pages": ["", RECEIPT, "", ""]},
    {"id": "punctuation_only_scan", "expected": "authorization", "pages": ["---\n□ □\n...", AUTHORIZATION]},
    {"id": "page_counter_only_scan", "expected": "authorization", "pages": ["1 / 2", "위임장"]},
    {"id": "two_covers_before_title", "expected": "invoice", "pages": [COVER, "보관 표지\n접수 번호: 789", "청구서"]},
    {"id": "cover_with_actual_fields_is_not_discarded", "expected": "unknown", "pages": [
        "신청서 표지\n신청인: 김한빛\n성명: 김한빛\n소속: 예시학교\n연락처: 010-0000-0000", RECEIPT]},
    {"id": "reference_before_real_form_stays_reference", "expected": "unknown", "reason": "reference_material", "pages": [
        "위임장 작성 가이드\n대리 제출 절차를 설명합니다.", AUTHORIZATION]},
    {"id": "reference_between_form_and_privacy", "expected": "authorization", "pages": [
        AUTHORIZATION, "제출 서류 목록\n영수증\n청구서", PRIVACY]},
    {"id": "split_guide_cannot_supply_memo_evidence", "expected": "unknown", "pages": ["보관 메모\n관리 번호: 12", SPLIT_GUIDE]},
    {"id": "split_policy_before_form_is_reference", "expected": "unknown", "reason": "reference_material", "pages": [SPLIT_POLICY, AUTHORIZATION]},
    {"id": "excluded_clinical_body_stays_unsupported", "expected": "unknown", "reason": "unsupported_document", "pages": [CLINICAL_FIELDS]},
    {"id": "clinical_form_is_not_school_reply_appendix", "expected": "unknown", "pages": [NOTICE, CLINICAL_FIELDS]},
    {"id": "unsupported_form_before_notice", "expected": "unknown", "pages": [CLINICAL_FIELDS, NOTICE]},
    {"id": "medical_context_privacy_form_is_supported", "expected": "consent", "pages": [
        "임상시험 개인정보 수집 이용 동의서\n수집 목적: 시험 참가자 관리\n수집 항목: 연락처\n보유 기간: 1년\n동의를 거부할 수 있습니다."]},
    {"id": "prescription_is_not_a_supported_form", "expected": "unknown", "pages": [
        "처방전\n환자 성명: 김한빛\n처방 약품: 시험용 예시\n복용 횟수: 하루 두 번\n의사 서명: 이새봄"]},
    {"id": "school_reply_remains_a_valid_appendix", "expected": "notice", "pages": [NOTICE, ACTIVITY]},
    {"id": "application_with_work_summary", "expected": "application", "pages": [APPLICATION, SUMMARY]},
    {"id": "summary_then_application_is_ambiguous", "expected": "unknown", "pages": [SUMMARY, APPLICATION]},
    {"id": "privacy_first_does_not_hide_authorization", "expected": "unknown", "pages": [PRIVACY, AUTHORIZATION]},
    {"id": "page_boundary_cannot_create_wage_keyword", "expected": "unknown", "pages": [
        "근로자: 김한빛\n근로시간: 하루 여섯 시간\n시", "급"]},
    {"id": "page_ids_determine_order_despite_delivery", "expected": "notice", "pages": [NOTICE, ACTIVITY], "reordered": True},
    {"id": "guide_cannot_complete_missing_form_fields", "expected": "unknown", "pages": [
        "위임인: 김한빛\n대리인: 이새봄", "위임장 작성 가이드\n위임 업무: 회원증 수령\n위임 기간: 하루"]},
    {"id": "named_cover_without_the_actual_form", "expected": "unknown", "pages": ["제출 서류 표지\n위임장"]},
]


class DocumentBoundaryTest(unittest.TestCase):
    def setUp(self):
        rules = json.loads((Path(__file__).resolve().parents[1] / "app/rules/doc_types.json").read_text("utf-8"))
        self.classifier = DocumentClassifier(rules)

    def test_document_boundaries(self):
        for case in BOUNDARY_CASES:
            with self.subTest(case=case["id"]):
                lines = blocks(case["pages"])
                if case.get("reordered"):
                    lines = [b.model_copy(update={"page": b.page * 3 + 7}) for b in lines]
                    lines.sort(key=lambda b: -b.page)
                actual = self.classifier.classify(lines)
                self.assertEqual(case["expected"], actual.doc_type.value)
                if case.get("reason"):
                    self.assertEqual(case["reason"], actual.reason)

    def test_recorded_clinical_title_typo_cannot_hide_unsupported_form(self):
        # Frozen OCR text from boundaries/results.json,
        # unsupported_primary_with_privacy/handheld (synthetic image input).
        clinical_ocr = (
            "_ 임상시험참가 통의서\n、 참가자:김한빛\n、 시험내용:시험용예시\n"
            "、 시험일:11월20일\n담당 연구원: 이새봄"
        )
        privacy_ocr = (
            "개인정보 수집이용 동의서\n_ 수집 목적:서류접수\n、 수집항목;성명 연락저\n"
            ". 보유 기간: 접수후한 달\n동의를 거부할 수있습니다."
        )
        for pages in ([clinical_ocr, privacy_ocr], [NOTICE, clinical_ocr, privacy_ocr]):
            with self.subTest(pages=len(pages)):
                actual = self.classifier.classify(blocks(pages))
                self.assertEqual("unknown", actual.doc_type.value)
                self.assertEqual("unsupported_document", actual.reason)

    def test_medical_privacy_and_incidental_typo_mentions_remain_supported(self):
        for ending in ("동의서", "통의서"):
            with self.subTest(ending=ending):
                text = "임상시험 개인정보 수집 이용 " + ending + "\n" + PRIVACY.split("\n", 1)[1]
                self.assertEqual("consent", self.classifier.classify(blocks([text])).doc_type.value)
        notice = NOTICE + "\n제출 서류: 임상시험 참가 통의서"
        self.assertEqual("notice", self.classifier.classify(blocks([notice])).doc_type.value)


if __name__ == "__main__":
    unittest.main()

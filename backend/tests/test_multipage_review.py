"""Synthetic, offline regressions for page boundaries and mixed form bundles."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType
from app.services.doc_classifier import DocumentClassifier
from document_corpus import blocks, variants


RULES = json.loads((Path(__file__).resolve().parents[1] / "app/rules/doc_types.json").read_text("utf-8"))
CLASSIFIER = DocumentClassifier(RULES)
FORMS = {
    "contract": "근로계약서\n근로자: 김가상\n시급: 12000원\n근로시간: 하루 6시간",
    "notice": "가정통신문\n학부모님께\n일시: 다음 주 수요일\n장소: 운동장\n준비물: 운동화",
    "consent": "개인정보 수집 이용 동의서\n수집 목적: 신청 확인\n수집 항목: 성명 연락처\n보유 기간: 한 달\n동의를 거부할 수 있습니다.",
    "application": "참가신청서\n신청인: 김가상\n성명: 김가상\n소속: 예시학교\n연락처: 010-0000-0000",
    "summary": "작품요약서\n작품명: 음성 지도\n팀명: 가상팀\n기획의도: 이동 지원\n사용 기술: 지도",
    "authorization": "위임장\n위임인: 김가상\n대리인: 이예시\n위임 업무: 서류 수령\n위임 기간: 하루",
    "certificate": "재직증명서\n성명: 김가상\n재직 기간: 2024년부터 현재\n발급 기관: 예시회사\n위 사실을 증명합니다.",
    "invoice": "청구서\n청구 금액: 20000원\n납부 기한: 다음 주\n청구 기관: 예시회사",
    "receipt": "영수증\n결제 금액: 20000원\n상호: 예시상점\n거래일: 오늘\n결제 완료",
    "pledge": "보안 서약서\n서약자: 김가상\n서약 내용: 자료를 안전하게 보관합니다.\n서약자 서명: 김가상",
    "report": "활동 보고서\n보고자: 김가상\n활동 내용: 현장 조사\n활동 결과: 점검 완료\n향후 계획: 재점검",
    "questionnaire": "만족도 설문지\n조사 목적: 시설 개선\n문항 1: 시설에 만족합니까?\n매우 만족 보통 매우 불만족",
    "activity_consent": "체험학습 참가 동의서\n활동명: 체험학습\n참가자: 김가상\n활동 일시: 다음 주\n참가에 동의합니다.",
}
PRIVACY = FORMS["consent"]
COVER = "제출 서류 표지\n예시기관\n접수 번호: 123"


def body(kind):
    return FORMS[kind].split("\n", 1)[1]


class MultipageReviewTest(unittest.TestCase):
    def test_cropped_main_form_keeps_its_type_with_privacy_appendix(self):
        for kind in FORMS:
            for variant, sample in variants(blocks([body(kind), PRIVACY])):
                with self.subTest(kind=kind, variant=variant):
                    self.assertEqual(kind, CLASSIFIER.classify(sample).doc_type.value)

    def test_cover_does_not_let_privacy_appendix_replace_primary_body(self):
        for kind in FORMS:
            with self.subTest(kind=kind):
                result = CLASSIFIER.classify(blocks([COVER, body(kind), PRIVACY]))
                self.assertEqual(kind, result.doc_type.value)

    def test_unrelated_cropped_secondary_forms_abstain(self):
        for first, second in (
            ("authorization", "receipt"), ("report", "invoice"),
            ("certificate", "questionnaire"), ("invoice", "pledge"),
            ("contract", "authorization"), ("summary", "contract"),
            ("consent", "activity_consent"),
        ):
            for variant, sample in variants(blocks([FORMS[first], body(second)])):
                with self.subTest(first=first, second=second, variant=variant):
                    result = CLASSIFIER.classify(sample)
                    self.assertEqual(DocType.UNKNOWN, result.doc_type)
                    self.assertEqual("conflicting_documents", result.reason)

    def test_cropped_contract_from_different_family_abstains(self):
        lease = "임대인: 김가상\n임차인: 이예시\n보증금: 1000만원\n임대차기간: 2년"
        for cover in ([], [COVER]):
            with self.subTest(cover=cover):
                result = CLASSIFIER.classify(blocks(cover + [FORMS["contract"], lease]))
                self.assertEqual(DocType.UNKNOWN, result.doc_type)
                self.assertEqual("conflicting_documents", result.reason)

    def test_later_reference_page_cannot_create_a_form(self):
        for kind, form in FORMS.items():
            guide = form.splitlines()[0] + " 작성 가이드\n" + body(kind)
            for variant, sample in variants(blocks(["보관 메모\n관리번호: 123", guide])):
                with self.subTest(kind=kind, variant=variant):
                    self.assertEqual(DocType.UNKNOWN, CLASSIFIER.classify(sample).doc_type)

    def test_reference_appendix_does_not_change_scores(self):
        guide = "청구서 작성 가이드\n" + body("invoice")
        for kind in FORMS:
            with self.subTest(kind=kind):
                primary = CLASSIFIER.classify(blocks([body(kind)]))
                attached = CLASSIFIER.classify(blocks([body(kind), guide]))
                self.assertEqual(primary.doc_type, attached.doc_type)
                self.assertEqual(primary.scores, attached.scores)

    def test_duplicate_pages_do_not_change_evidence_scores(self):
        for kind, form in FORMS.items():
            with self.subTest(kind=kind):
                primary = CLASSIFIER.classify(blocks([form]))
                repeated = CLASSIFIER.classify(blocks([form] * 3))
                self.assertEqual(primary.doc_type, repeated.doc_type)
                self.assertEqual(primary.scores, repeated.scores)

    def test_continuation_pages_can_complete_body_evidence(self):
        for kind, pages in (
            ("authorization", ["위임인: 김가상\n대리인: 이예시", "위임 업무: 서류 수령\n위임 기간: 하루"]),
            ("invoice", ["청구 금액: 20000원", "납부 기한: 다음 주\n청구 기관: 예시회사"]),
            ("report", ["보고자: 김가상\n활동 내용: 현장 조사", "활동 결과: 점검 완료\n향후 계획: 재점검"]),
        ):
            with self.subTest(kind=kind):
                self.assertEqual(kind, CLASSIFIER.classify(blocks(pages)).doc_type.value)

    def test_cover_preserves_the_first_actual_form_title(self):
        for kind, form in FORMS.items():
            with self.subTest(kind=kind):
                self.assertEqual(kind, CLASSIFIER.classify(blocks([COVER, form.splitlines()[0]])).doc_type.value)


if __name__ == "__main__":
    unittest.main()

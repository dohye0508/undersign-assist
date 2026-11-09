"""Independent row/cell boundary checks; all AI responses are mocked offline."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType
from app.services import doc_reader, llm
from document_corpus import blocks


def extracted(kind, text):
    return {f.label: f.value for f in doc_reader._extract_by_rules(blocks([text]), DocType(kind))}


def ai_read(kind, text, values):
    lines = blocks([text])
    with patch.object(llm, "ask_json", return_value={"doc_type": kind, "fields": values}):
        return doc_reader._read_with_ai(text, lines, DocType(kind))


class RowBoundaryTest(unittest.TestCase):
    def test_contract_salary_and_payday_are_separate_cells(self):
        actual = extracted("contract", "근로계약서\n시급: 15000원    임금 지급일: 매월 25일")
        self.assertEqual({"임금": "15000원", "임금 지급일": "매월 25일"}, actual)

    def test_notice_keeps_time_colons_but_stops_at_place_label(self):
        actual = extracted("notice", "가정통신문\n일시: 11월 9일 09:30    장소: 예시도서관")
        self.assertEqual("11월 9일 09:30", actual["날짜"])
        self.assertEqual("예시도서관", actual["장소"])

    def test_privacy_purpose_items_and_retention_do_not_bleed(self):
        actual = extracted("consent", "개인정보 동의서\n수집 목적: 행사 접수 | 수집 항목: 성명 연락처 | 보유 기간: 1개월")
        self.assertEqual({"수집 목적": "행사 접수", "수집 항목": "성명 연락처", "보유 기간": "1개월"}, actual)

    def test_applicant_name_contact_and_email_share_one_row(self):
        actual = extracted("application", "참가 신청서\n신청인 성명: 김가상 연락처: 010-1111-2222 이메일: person@example.com")
        self.assertEqual("김가상", actual["성명"])
        self.assertEqual("010-1111-2222", actual["연락처"])
        self.assertEqual("person@example.com", actual["이메일"])

    def test_certificate_subject_after_representative_on_same_row(self):
        actual = extracted("certificate", "재직증명서\n대표자 성명: 박대표    대상자 성명: 김대상")
        self.assertEqual("김대상", actual["성명"])

    def test_authorization_parties_and_scope_share_one_row(self):
        actual = extracted("authorization", "위임장\n위임인: 김위임 | 수임인: 이수임 | 위임 사항: 증명서 수령")
        self.assertEqual({"위임인": "김위임", "대리인": "이수임", "위임 업무": "증명서 수령"}, actual)

    def test_invoice_amount_due_and_account_are_separate(self):
        actual = extracted("invoice", "청구서\n청구 금액: 85000원 납부 기한: 11월 30일 납부 계좌: 예시은행 123-456")
        self.assertEqual("85000원", actual["청구 금액"])
        self.assertEqual("11월 30일", actual["납부 기한"])
        self.assertEqual("예시은행 123-456", actual["납부 방법"])

    def test_report_result_stops_before_next_plan(self):
        actual = extracted("report", "조사 보고서\n조사 결과: 안내판 교체 필요 향후 계획: 다음 달 재점검")
        self.assertEqual("안내판 교체 필요", actual["결과"])
        self.assertEqual("다음 달 재점검", actual["향후 계획"])

    def test_label_words_inside_a_value_remain_content(self):
        actual = extracted("summary", "작품 요약서\n작품명: 이름 없는 도시\n작품 요약: 장소와 시간의 관계를 탐구")
        self.assertEqual("이름 없는 도시", actual["작품명"])
        self.assertEqual("장소와 시간의 관계를 탐구", actual["요약"])

    def test_blank_first_cell_cannot_borrow_second_cells_value(self):
        actual = extracted("application", "참가 신청서\n성명:    연락처: 010-1111-2222")
        self.assertNotIn("성명", actual)
        self.assertEqual("010-1111-2222", actual["연락처"])

    def test_blank_first_cell_cannot_borrow_the_next_physical_row(self):
        actual = extracted("application", "참가 신청서\n성명: | 연락처: 010-1111-2222\n다른 설명문")
        self.assertNotIn("성명", actual)

    def test_guardian_contact_inherits_its_owner_on_a_shared_row(self):
        actual = extracted("application", "참가 신청서\n보호자 성명: 박보호 연락처: 010-3333-4444\n신청인 성명: 김신청")
        self.assertNotIn("연락처", actual)
        self.assertEqual("김신청", actual["성명"])

    def test_compact_guardian_contact_also_owns_following_email(self):
        actual = extracted("application", "참가 신청서\n보호자연락처: 010-3333-4444 이메일: guardian@example.com\n신청인 성명: 김신청")
        self.assertNotIn("연락처", actual)
        self.assertNotIn("이메일", actual)


class AmountAndBlankTest(unittest.TestCase):
    def test_receipt_payment_is_separate_from_following_refund(self):
        for row in ("결제 금액: 12000원 환불 금액: 2000원", "환불 금액: 2000원 결제 금액: 12000원"):
            with self.subTest(row=row):
                self.assertEqual("12000원", extracted("receipt", "영수증\n" + row)["결제 금액"])

    def test_receipt_refund_and_discount_only_never_become_payment(self):
        actual = extracted("receipt", "영수증\n환불 금액: 2000원 할인 금액: 1000원\n상호: 예시문구점")
        self.assertNotIn("결제 금액", actual)

    def test_signed_amount_keeps_its_minus_sign(self):
        self.assertEqual("-5000원", extracted("invoice", "청구서\n청구 금액: -5000원")["청구 금액"])

    def test_leading_decimal_point_is_not_stripped(self):
        self.assertEqual(".5만원", extracted("receipt", "영수증\n결제 금액: .5만원")["결제 금액"])

    def test_signature_and_underscore_placeholders_are_not_values(self):
        for placeholder in ("(서명)", "(인)", "____", "---"):
            with self.subTest(placeholder=placeholder):
                self.assertNotIn("위임인", extracted("authorization", "위임장\n위임인: " + placeholder))

    def test_brackets_in_real_company_value_are_preserved(self):
        self.assertEqual("예시회사(주)", extracted("certificate", "재직증명서\n발급 기관: 예시회사(주)")["발급 기관"])


class AiCompleteEvidenceTest(unittest.TestCase):
    def test_ai_cannot_shorten_a_persons_name(self):
        with self.assertRaises(llm.LlmError):
            ai_read("certificate", "재직증명서\n대상자 성명: 김가상", {"성명": "김"})

    def test_ai_cannot_drop_a_korean_amount_unit(self):
        with self.assertRaises(llm.LlmError):
            ai_read("invoice", "청구서\n청구 금액: 5만원", {"청구 금액": "5"})

    def test_ai_cannot_shorten_a_decimal_amount(self):
        with self.assertRaises(llm.LlmError):
            ai_read("invoice", "청구서\n청구 금액: 1.5만원", {"청구 금액": "1"})

    def test_ai_valid_signed_amount_remains_valid(self):
        actual = ai_read("invoice", "청구서\n청구 금액: -5000원", {"청구 금액": "-5000원"})
        self.assertEqual("-5000원", actual[0].value)

    def test_ai_valid_values_in_shared_row_keep_original_row(self):
        actual = ai_read("application", "참가 신청서\n신청인 성명: 김가상 연락처: 010-1111-2222", {
            "성명": "김가상", "연락처": "010-1111-2222",
        })
        self.assertEqual([("성명", 1), ("연락처", 1)], [(f.label, f.line) for f in actual])

    def test_ai_format_normalization_keeps_commas_and_unicode_equivalent(self):
        actual = ai_read("invoice", "청구서\n청구 금액: １５,０００원", {"청구 금액": "15000원"})
        self.assertEqual("15000원", actual[0].value)


class RecordedOcrBoundaryTest(unittest.TestCase):
    def test_recorded_application_last_cells_continue_on_next_ocr_rows(self):
        # Verbatim OCR from samples/boundaries/results.json, inline_application/clean.
        actual = extracted("application", "참가 신청서\n신청인성명: 김가상_ 연락처:\n010-1111-2222\n"
                           "이메일:0라5000@6×30016.000ㅁ, 소속:\n예시학교")
        self.assertEqual("김가상", actual["성명"])
        self.assertEqual("010-1111-2222", actual["연락처"])
        self.assertEqual("예시학교", actual["소속"])
        self.assertEqual("0라5000@6×30016.000ㅁ,", actual["이메일"])

    def test_recorded_decorations_end_at_known_next_field(self):
        for kind, text, label, expected in (
            ("contract", "근로계약서\n시급:15000원_ 임금지급일:매월25일", "임금", "15000원"),
            ("contract", "근로계약서\n시급:15000원、 임금지급일:매월25일", "임금", "15000원"),
            ("receipt", "영수증\n결제금액:12000원_환불금액:2000원", "결제 금액", "12000원"),
            ("receipt", "영수증\n상호: 예시 문구점_거래 일:2026년11월9일", "상호", "예시 문구점"),
        ):
            with self.subTest(kind=kind, text=text):
                self.assertEqual(expected, extracted(kind, text)[label])

    def test_only_final_blank_cell_can_take_next_rows_value(self):
        actual = extracted("application", "참가 신청서\n성명: | 연락처:\n010-1111-2222")
        self.assertNotIn("성명", actual)
        self.assertEqual("010-1111-2222", actual["연락처"])
        across_pages = doc_reader._extract_by_rules(blocks(["참가 신청서\n성명: | 연락처:", "010-1111-2222"]), DocType.APPLICATION)
        self.assertNotIn("연락처", {field.label for field in across_pages})

    def test_boundary_cleanup_preserves_internal_underscores_and_signed_ocr_values(self):
        actual = extracted("application", "참가 신청서\n이메일: team_one@example.com_ 소속: Team_One")
        self.assertEqual("team_one@example.com", actual["이메일"])
        self.assertEqual("Team_One", actual["소속"])
        self.assertEqual("-16000원", extracted("receipt", "영수증\n결제 금액: -16000원_ 환불 금액: 2000원")["결제 금액"])
        self.assertEqual("keep_", extracted("summary", "작품 요약서\n작품명: keep_")["작품명"])

    def test_ai_points_to_continued_last_cell_value_row(self):
        actual = ai_read("application", "참가 신청서\n신청인 성명: 김가상_ 연락처:\n010-1111-2222", {
            "성명": "김가상", "연락처": "010-1111-2222",
        })
        self.assertEqual([("성명", 1), ("연락처", 2)], [(field.label, field.line) for field in actual])


if __name__ == "__main__":
    unittest.main()

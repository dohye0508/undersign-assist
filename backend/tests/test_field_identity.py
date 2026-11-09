"""Offline field ownership regressions, including mocked AI source checks."""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType
from app.services import doc_reader, llm
from document_corpus import blocks


def fields(text, kind):
    return {field.label: field.value for field in doc_reader._extract_by_rules(blocks([text]), DocType(kind))}


class SubjectOwnershipTest(unittest.TestCase):
    def test_certificate_subject_is_not_issuer_representative(self):
        for subject in ("신청인", "대상자", "근로자"):
            text = f"재직증명서\n대표자 성명: 박대표\n대표자 소속: 발급팀\n{subject} 성명: 김신청\n{subject} 소속: 개발팀"
            for source in (text, " ".join(text).replace(" \n ", "\n")):
                with self.subTest(subject=subject, spaced=source != text):
                    actual = fields(source, "certificate")
                    self.assertEqual("김신청", doc_reader.compact(actual["성명"]))
                    self.assertEqual("개발팀", doc_reader.compact(actual["소속"]))

    def test_certificate_explicit_subject_wins_over_longer_applicant_label(self):
        for subject_lines in ("대상자: 김대상\n대상자 소속: 개발팀", "대상자\n성명: 김대상\n소속: 개발팀"):
            with self.subTest(subject_lines=subject_lines):
                actual = fields(
                    "재직증명서\n신청인 성명: 박신청\n신청인 소속: 접수팀\n" + subject_lines, "certificate"
                )
                self.assertEqual("김대상", actual["성명"])
                self.assertEqual("개발팀", actual["소속"])

    def test_blank_certificate_subject_cannot_be_replaced_by_requester(self):
        actual = fields("재직증명서\n신청인 성명: 박신청\n신청인 소속: 접수팀\n대상자 성명:", "certificate")
        self.assertNotIn("성명", actual)
        self.assertNotIn("소속", actual)

    def test_absent_subject_is_not_filled_from_other_people(self):
        cases = (
            ("certificate", "재직증명서", "성명"),
            ("application", "참가 신청서", "성명"),
            ("summary", "작품 요약서", "참가자"),
            ("pledge", "보안 서약서", "서약자"),
        )
        for kind, title, label in cases:
            for owner in ("대표자", "보호자", "담당자", "법정대리인"):
                with self.subTest(kind=kind, owner=owner):
                    actual = fields(title + f"\n{owner} 성명: 박대리\n{owner} 소속: 발급팀", kind)
                    self.assertNotIn(label, actual)
                    self.assertNotIn("소속", actual)

    def test_application_contact_and_email_belong_to_applicant(self):
        actual = fields(
            "참가 신청서\n보호자 성명: 박보호\n담당자 연락처: 02-123-4567\n"
            "담당자 이메일: office@example.com\n신청인 성명: 김신청\n"
            "신청인 연락처: 010-1111-2222\n신청인 이메일: person@example.com", "application"
        )
        self.assertEqual("김신청", actual["성명"])
        self.assertEqual("010-1111-2222", actual["연락처"])
        self.assertEqual("person@example.com", actual["이메일"])

    def test_separate_party_sections_keep_generic_names_with_their_owner(self):
        actual = fields(
            "재직증명서\n대표자\n성명: 박대표\n소속: 발급팀\n신청인\n성명: 김신청\n소속: 개발팀", "certificate"
        )
        self.assertEqual("김신청", actual["성명"])
        self.assertEqual("개발팀", actual["소속"])
        self.assertNotIn("성명", fields("재직증명서\n대표자\n성명: 박대표", "certificate"))

    def test_party_context_does_not_cross_pages(self):
        actual = doc_reader._extract_by_rules(blocks(["재직증명서\n대표자", "성명: 김신청"]), DocType.CERTIFICATE)
        self.assertEqual("김신청", {field.label: field.value for field in actual}["성명"])

    def test_unqualified_names_still_work_when_no_other_owner_is_named(self):
        for kind, title, label in (
            ("certificate", "재직증명서", "성명"),
            ("application", "참가 신청서", "성명"),
            ("summary", "작품 요약서", "참가자"),
            ("pledge", "보안 서약서", "서약자"),
        ):
            with self.subTest(kind=kind):
                self.assertEqual("김신청", fields(title + "\n성명:\n김신청", kind)[label])

    def test_empty_subject_cannot_take_a_role_heading_as_its_name(self):
        self.assertNotIn("성명", fields("재직증명서\n성명:\n대표자\n박대표", "certificate"))


class LabelOwnershipTest(unittest.TestCase):
    def test_payday_cannot_be_read_as_pay(self):
        actual = fields("근로계약서\n임금 지급일: 매월 25일", "contract")
        self.assertNotIn("임금", actual)
        self.assertEqual("매월 25일", actual["임금 지급일"])

    def test_party_contact_cannot_be_read_as_party_name(self):
        for kind, title, owner, label in (
            ("activity_consent", "체험학습 참가 동의서", "보호자", "보호자"),
            ("authorization", "위임장", "위임인", "위임인"),
            ("report", "업무 보고서", "보고자", "보고자"),
        ):
            with self.subTest(kind=kind):
                self.assertNotIn(label, fields(title + f"\n{owner} 연락처: 010-1111-2222", kind))
                actual = fields(title + f"\n{owner} 연락처: 010-1111-2222\n{owner} 성명: 김신청", kind)
                self.assertEqual("김신청", actual[label])

    def test_blank_specific_name_does_not_fall_back_to_label_suffix(self):
        for kind, title, owner, label in (
            ("certificate", "재직증명서", "대상자", "성명"),
            ("activity_consent", "체험학습 참가 동의서", "보호자", "보호자"),
            ("authorization", "위임장", "위임인", "위임인"),
        ):
            with self.subTest(kind=kind):
                self.assertNotIn(label, fields(title + f"\n{owner} 성명:\n발급 기관: 예시기관", kind))


class AiOwnershipTest(unittest.TestCase):
    def test_ai_cannot_choose_requester_when_certificate_names_another_subject(self):
        lines = blocks(["재직증명서\n신청인 성명: 박신청\n대상자: 김대상"])
        answer = {"doc_type": "certificate", "fields": {"성명": "박신청"}}
        with patch.object(llm, "available", return_value=True), patch.object(llm, "ask_json", return_value=answer):
            _, _, actual, reader = doc_reader.read(lines)
        self.assertEqual("rules", reader)
        self.assertEqual("김대상", {field.label: field.value for field in actual}["성명"])

    def test_ai_cannot_supply_a_representatives_name_for_missing_subject(self):
        lines = blocks(["재직증명서\n대표자 성명: 박대표\n발급 기관: 예시회사"])
        answer = {"doc_type": "certificate", "fields": {"성명": "박대표", "발급 기관": "예시회사"}}
        with patch.object(llm, "available", return_value=True), patch.object(llm, "ask_json", return_value=answer):
            kind, _, actual, reader = doc_reader.read(lines)
        self.assertEqual(DocType.CERTIFICATE, kind)
        self.assertEqual("rules", reader)
        self.assertNotIn("성명", {field.label for field in actual})
        self.assertNotIn("박대표", doc_reader.build_speech(kind, actual, lines))

    def test_ai_uses_owned_source_when_same_name_occurs_elsewhere_first(self):
        lines = blocks(["재직증명서\n대표자 성명: 김동명\n신청인 성명: 김동명"])
        answer = {"doc_type": "certificate", "fields": {"성명": "김동명"}}
        with patch.object(llm, "ask_json", return_value=answer):
            actual = doc_reader._read_with_ai("\n".join(line.text for line in lines), lines, DocType.CERTIFICATE)
        self.assertEqual([("성명", "김동명", 2)], [(field.label, field.value, field.line) for field in actual])

    def test_ai_cannot_read_contact_as_a_name(self):
        lines = blocks(["체험학습 참가 동의서\n보호자 연락처: 010-1111-2222"])
        answer = {"doc_type": "activity_consent", "fields": {"보호자": "010-1111-2222"}}
        with patch.object(llm, "ask_json", return_value=answer):
            with self.assertRaises(llm.LlmError):
                doc_reader._read_with_ai("\n".join(line.text for line in lines), lines, DocType.ACTIVITY_CONSENT)

    def test_ai_cannot_truncate_number_using_another_fields_short_number(self):
        lines = blocks(["청구서\n청구 금액: 15000\n고객 번호: 1"])
        answer = {"doc_type": "invoice", "fields": {"청구 금액": "1"}}
        with patch.object(llm, "ask_json", return_value=answer):
            with self.assertRaises(llm.LlmError):
                doc_reader._read_with_ai("\n".join(line.text for line in lines), lines, DocType.INVOICE)


if __name__ == "__main__":
    unittest.main()

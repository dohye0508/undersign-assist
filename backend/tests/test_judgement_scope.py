"""A missing analysis is not a successful legal check; never invent work hours."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.models import DocType, RecognizedDocument
from app.services import doc_reader, judge, llm
from app.services.judge.parse import parse_hours_per
from document_corpus import blocks


def document(kind, text):
    lines = blocks([text])
    with patch.object(llm, "available", return_value=False):
        fields = doc_reader._extract_by_rules(lines, DocType(kind))
    return RecognizedDocument(doc_type=kind, blocks=lines, full_text=text, fields=fields)


class JudgementScopeTest(unittest.TestCase):
    def test_calendar_day_is_not_a_daily_schedule(self):
        for text in ("11일 8시간", "2026년 11월 21일 8시간"):
            self.assertIsNone(parse_hours_per(text, "day"))

    def test_unclassified_document_does_not_sound_cleared(self):
        result = judge.run(document("unknown", "여러 종류의 서류\n문서 내용을 확인하세요"))
        self.assertNotIn("특별히 확인이 필요한 항목을 찾지 못했어요", result["speech"])
        self.assertIn("판단", result["speech"])
        self.assertTrue(result["findings"])

    def test_unsupported_contract_does_not_sound_cleared(self):
        result = judge.run(document("contract", "계약서\n당사자는 다음 조건을 정합니다"))
        self.assertNotIn("특별히 확인이 필요한 항목을 찾지 못했어요", result["speech"])
        self.assertTrue(result["findings"])

    def test_existing_nonlegal_forms_receive_their_own_reading_checks(self):
        for kind, text in (("application", "신청서\n성명: 김예시"), ("summary", "작품요약서\n작품명: 도우미")):
            with self.subTest(kind=kind), patch.object(judge.E, "extract", side_effect=AssertionError("not a contract")):
                result = judge.run(document(kind, text))
                self.assertEqual(kind, result["subtype"])
                self.assertTrue(all(f["level"] == "info" and not f["basis"] for f in result["findings"]))

    def test_missing_schedule_does_not_invent_forty_hour_week(self):
        for schedule in ("", "소정근로시간: 1일 8시간", "근무일: 주3일", "소정근로시간: 주0시간"):
            with self.subTest(schedule=schedule):
                doc = document("contract", "근로계약서\n근로자: 김예시\n월급: 100만원\n" + schedule)
                with patch.object(judge.F, "hourly_from_monthly", wraps=judge.F.hourly_from_monthly) as convert:
                    result = judge.run(doc)
                convert.assert_not_called()
                self.assertFalse(any(f["rule_id"] == "LAB-003" for f in result["findings"]))
                self.assertTrue(any(f["rule_id"] == "work_hours_unread" for f in result["findings"]))

    def test_weekly_hours_alone_selects_part_time_rules(self):
        result = judge.run(document("contract", "근로계약서\n근로자: 김예시\n소정근로시간: 주10시간\n시급: 12000원"))
        self.assertEqual("labor_part_time", result["subtype"])

    def test_explicit_daily_hours_and_days_still_convert(self):
        doc = document("contract", "근로계약서\n근로자: 김예시\n월급: 160만원\n소정근로시간: 1일 8시간\n근무일: 주3일")
        with patch.object(judge.F, "hourly_from_monthly", wraps=judge.F.hourly_from_monthly) as convert:
            judge.run(doc)
        convert.assert_called_once_with(1600000, 24)

    def test_standalone_schedule_is_not_treated_as_missing(self):
        doc = document("contract", "근로계약서\n근로자: 김예시\n월급: 160만원\n일 8시간 주 3일")
        with patch.object(judge.F, "hourly_from_monthly", wraps=judge.F.hourly_from_monthly) as convert:
            judge.run(doc)
        convert.assert_called_once_with(1600000, 24)

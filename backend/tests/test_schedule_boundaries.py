"""Clock and schedule inputs must not invent hours from malformed OCR."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.judge import parse as P
from app.services import judge
from test_judgement_scope import document


class ScheduleBoundaryTest(unittest.TestCase):
    def test_regular_clock_range(self):
        for text in ("09:00~18:00", "9시 00분부터 18시 00분"):
            self.assertEqual((9, 18), P.parse_time_range(text))

    def test_overnight_range(self):
        self.assertEqual((22, 30), P.parse_time_range("22:00~06:00"))

    def test_overnight_break(self):
        self.assertEqual(20, P.parse_minutes("휴게 23:50~00:10"))

    def test_invalid_break_clock_is_not_read_as_plain_minutes(self):
        self.assertIsNone(P.parse_minutes("휴게 9시 90분~10시 00분"))

    def test_twelve_hour_markers(self):
        for text, expected in (("오전 9시~오후 6시", (9, 18)), ("오후 10시부터 오전 6시", (22, 30)),
                               ("오전 12시~오후 12시", (0, 12)), ("오후 12시~오후 1시", (12, 13))):
            with self.subTest(text=text):
                self.assertEqual(expected, P.parse_time_range(text))

    def test_invalid_clock_fields_are_not_salvaged(self):
        for text in ("29:00~30:00", "09:80~18:00", "109:00~18:00", "09:00~18:990", "09:00~24:01"):
            with self.subTest(text=text):
                self.assertIsNone(P.parse_time_range(text))

    def test_incomplete_clock_is_not_zero_minutes(self):
        for text in ("09:~18:00", "09:00~18:", "오후 13시~오후 14시"):
            with self.subTest(text=text):
                self.assertIsNone(P.parse_time_range(text))

    def test_equal_endpoints_are_ambiguous(self):
        self.assertIsNone(P.parse_time_range("09:00~09:00"))

    def test_midnight_end(self):
        self.assertEqual((16, 24), P.parse_time_range("16:00~24:00"))

    def test_daily_hour_limits(self):
        for text in ("일 25시간", "하루 80시간"):
            self.assertIsNone(P.parse_hours_per(text, "day"))

    def test_spaced_calendar_day_is_not_daily_hours(self):
        self.assertIsNone(P.parse_hours_per("21 일 8시간", "day"))

    def test_weekly_hour_limits(self):
        self.assertIsNone(P.parse_hours_per("주 169시간", "week"))

    def test_multweek_period_is_not_one_week(self):
        for text in ("2주 40시간", "11주 40시간", "격주 20시간", "2 주 40시간", "격 주 20시간"):
            with self.subTest(text=text):
                self.assertIsNone(P.parse_hours_per(text, "week"))

    def test_valid_weekly_prefixes(self):
        for text in ("주 24시간", "1주 24시간", "매주 24시간", "일주일 24시간"):
            self.assertEqual(24, P.parse_hours_per(text, "week"))

    def test_impossible_or_alternating_workdays(self):
        for text in ("주 8일", "주 0일", "격주 3일", "2주 5일", "2 주 5일", "격 주 3일"):
            with self.subTest(text=text):
                self.assertIsNone(P.parse_days_per_week(text))

    def test_full_weekday_names_count_once(self):
        for text in ("매주 월요일, 수요일", "매주 월, 수", "매주 월요일 · 수요일"):
            self.assertEqual(2, P.parse_days_per_week(text))

    def test_weekday_range_crossing_sunday(self):
        for text, expected in (("월~금", 5), ("금~월", 4), ("월요일부터 금요일", 5)):
            self.assertEqual(expected, P.parse_days_per_week(text))

    def test_bad_schedule_does_not_drive_wage_conversion(self):
        doc = document("contract", "근로계약서\n근로자: 김예시\n월급: 160만원\n근로시간: 09:80~18:00\n휴게시간: 1시간\n근무일: 주5일")
        with patch.object(judge.F, "hourly_from_monthly", wraps=judge.F.hourly_from_monthly) as convert:
            result = judge.run(doc)
        convert.assert_not_called()
        self.assertTrue(any(f["rule_id"] == "work_hours_unread" for f in result["findings"]))

    def test_overnight_schedule_drives_correct_hours(self):
        doc = document("contract", "근로계약서\n근로자: 김예시\n월급: 160만원\n근로시간: 22:00~06:00\n휴게시간: 1시간\n근무일: 주3일")
        with patch.object(judge.F, "hourly_from_monthly", wraps=judge.F.hourly_from_monthly) as convert:
            judge.run(doc)
        convert.assert_called_once_with(1600000, 21)

"""Monetary unit arithmetic regressions: no statutory rules or rates here."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.judge.parse import parse_money


class MoneyParsingTest(unittest.TestCase):
    def test_mixed_arabic_and_korean_units(self):
        cases = {
            "보증금 5천만원": 50_000_000,
            "보증금1억5천만원": 150_000_000,
            "금액 1만2천원": 12_000,
            "1억 5천 2백 30만 4천 5백 67원": 152_304_567,
            "1억5원": 100_000_005,
            "1조 2억 3만 4원": 1_000_200_030_004,
            "3백50만원": 3_500_000,
            "5000만원": 50_000_000,
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(expected, parse_money(text))

    def test_decimal_unit_coefficients_are_exact(self):
        for text, expected in (("1.5만원", 15_000), ("0.3억원", 30_000_000),
                               ("1.25천원", 1_250), ("0.0001만원", 1),
                               ("1,000.5만원", 10_005_000), ("1.5원", None)):
            with self.subTest(text=text):
                self.assertEqual(expected, parse_money(text))

    def test_original_arabic_hangul_zero_and_ocr_forms(self):
        cases = {"시급 10,000원": 10_000, "금 오천만원정": 50_000_000,
                 "이백오십만원": 2_500_000, "일억오천만원": 150_000_000,
                 "천만원": 10_000_000, "만원": 10_000,
                 "0원": 0, "영원": 0, "0만원": 0,
                 "시급 1O,OOO원": 10_000, "금액 미정": None, "": None}
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(expected, parse_money(text))

    def test_malformed_amount_does_not_fall_back_to_valid_suffix(self):
        for text in ("1..5만원", "1,00원", "1만만원", "1천백천원", "1만2억원",
                     "-500원", "+500원", "일이만원", "..500원"):
            with self.subTest(text=text):
                self.assertIsNone(parse_money(text))


if __name__ == "__main__":
    unittest.main()

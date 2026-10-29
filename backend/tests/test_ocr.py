"""Geometry and bounded OCR fallback tests; no Tesseract executable required."""

import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageDraw
from app.models import Box, TextBlock
from app.services import ocr


def line(text, confidence, box=None):
    return ocr._Line(TextBlock(text=text, box=box or Box(x=10, y=20, width=100, height=30)), confidence)


class OcrGeometryTest(unittest.TestCase):
    def test_inverse_rotation_contains_original_pixels(self):
        # The image supplies the expected geometry independently of our formulas.
        mask = Image.new("L", (320, 180))
        ImageDraw.Draw(mask).rectangle((21, 37, 114, 75), fill=255)
        for angle, transpose in ((90, Image.Transpose.ROTATE_90),
                                 (180, Image.Transpose.ROTATE_180),
                                 (270, Image.Transpose.ROTATE_270)):
            with self.subTest(angle=angle):
                left, top, right, bottom = mask.transpose(transpose).getbbox()
                restored = ocr._original_box(Box(x=left, y=top, width=right-left, height=bottom-top), angle, *mask.size)
                self.assertEqual(mask.getbbox(), (restored.x, restored.y, restored.x + restored.width, restored.y + restored.height))

    def test_exif_rotation_dimensions_match_photo_coordinates(self):
        image = Image.new("RGB", (320, 180), "white")
        exif = Image.Exif()
        exif[274] = 6
        output = io.BytesIO()
        image.save(output, "JPEG", exif=exif)
        self.assertEqual((180, 320), ocr._open(output.getvalue()).size)

    def test_shadow_correction_preserves_size_and_clean_images(self):
        clean = Image.new("L", (320, 180), 255)
        ImageDraw.Draw(clean).rectangle((30, 30, 120, 40), fill=0)
        self.assertEqual(clean.tobytes(), ocr._flatten_lighting(clean).tobytes())
        shadow = Image.new("L", (320, 180), 110)
        ImageDraw.Draw(shadow).rectangle((30, 30, 120, 40), fill=55)
        corrected = ocr._flatten_lighting(shadow)
        self.assertEqual(shadow.size, corrected.size)
        self.assertGreater(corrected.getpixel((250, 90)) - corrected.getpixel((60, 35)), 150)

    def test_shadow_correction_keeps_sparse_marks(self):
        page = Image.new("L", (320, 180), 110)
        ImageDraw.Draw(page).rectangle((30, 30, 40, 33), fill=55)
        corrected = ocr._flatten_lighting(page)
        self.assertGreater(corrected.getpixel((250, 90)) - corrected.getpixel((35, 31)), 150)


class OcrFallbackTest(unittest.TestCase):
    def setUp(self):
        self.image = Image.new("RGB", (1600, 900), "white")
        ImageDraw.Draw(self.image).rectangle((20, 20, 1400, 50), fill="black")
        self.text = "개인정보 수집 목적 수집 항목 보유 기간 동의를 거부할 권리가 있습니다. " * 2

    def test_good_image_uses_only_normal_two_passes(self):
        with patch.object(ocr, "_tesseract_lines", side_effect=[[line(self.text, 90)], []]) as recognize:
            result = ocr._tesseract(self.image)
        self.assertEqual(2, recognize.call_count)
        self.assertEqual(self.text, result[0].text)

    def test_empty_page_does_not_attempt_rotations(self):
        with patch.object(ocr, "_tesseract_lines", return_value=[]) as recognize:
            self.assertEqual([], ocr._tesseract(Image.new("RGB", (1600, 900), "white")))
        self.assertEqual(2, recognize.call_count)

    def test_rotation_selection_preserves_reading_order_and_original_boxes(self):
        upright = [line(self.text, 90, Box(x=60, y=100, width=700, height=40)),
                   line("두번째 줄입니다", 90, Box(x=60, y=180, width=300, height=40))]
        with patch.object(ocr, "_tesseract_lines", side_effect=[
            [line("ㅇㅁ", 20)], upright, [], [], [],
        ]) as recognize:
            result = ocr._tesseract(self.image)
        self.assertEqual(5, recognize.call_count)
        self.assertEqual([self.text, "두번째 줄입니다"], [b.text for b in result])
        self.assertEqual(Box(x=1460, y=60, width=40, height=700), result[0].box)
        self.assertEqual(Box(x=1380, y=60, width=40, height=300), result[1].box)

    def test_unreliable_rotations_do_not_replace_original(self):
        with patch.object(ocr, "_tesseract_lines", side_effect=[
            [line("읽을 수 있는 원문", 50)], [line("가짜", 30)], [], [], [],
        ]):
            result = ocr._tesseract(self.image)
        self.assertEqual("읽을 수 있는 원문", result[0].text)


if __name__ == "__main__":
    unittest.main()

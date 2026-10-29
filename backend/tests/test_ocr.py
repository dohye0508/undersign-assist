"""Geometry and bounded OCR fallback tests; no Tesseract executable required."""

import io
import json
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

    def test_fine_rotation_boxes_enclose_original_ink(self):
        mask = Image.new("L", (420, 260))
        ImageDraw.Draw(mask).rectangle((31, 45, 186, 73), fill=255)
        for angle in (-17.5, -5, 3.5, 14):
            with self.subTest(angle=angle):
                rotated = mask.rotate(angle, Image.Resampling.BICUBIC, expand=True)
                x, y, right, bottom = rotated.getbbox()
                restored = ocr._unrotate_box(Box(x=x, y=y, width=right-x, height=bottom-y), angle, mask.size, rotated.size)
                self.assertLessEqual(restored.x, 31)
                self.assertLessEqual(restored.y, 45)
                self.assertGreaterEqual(restored.x + restored.width, 187)
                self.assertGreaterEqual(restored.y + restored.height, 74)
                self.assertLessEqual(restored.x + restored.width, mask.width)
                self.assertLessEqual(restored.y + restored.height, mask.height)

    def test_dark_screen_inverts_but_shaded_paper_does_not(self):
        for background, text, inverted in ((10, 230, True), (100, 10, False), (255, 0, False)):
            image = Image.new("L", (320, 180), background)
            ImageDraw.Draw(image).rectangle((30, 30, 150, 40), fill=text)
            actual = ocr._light_background(image)
            self.assertEqual(255-background if inverted else background, actual.getpixel((0, 0)))

    def test_two_columns_keep_unpaired_last_left_line_before_right(self):
        # Right baselines begin a few pixels BEFORE the corresponding left ones.
        header = TextBlock(text="문서 제목", box=Box(x=20, y=5, width=700, height=25))
        left = [TextBlock(text=f"왼쪽 본문 항목 {i}", box=Box(x=20, y=60+i*50, width=250, height=25)) for i in range(4)]
        right = [TextBlock(text=f"오른쪽 본문 항목 {i}", box=Box(x=600, y=58+i*50, width=250, height=25)) for i in range(3)]
        self.assertEqual([header, *left, *right], ocr._reading_order([*right, header, *left]))

    def test_short_table_labels_do_not_become_columns(self):
        labels = [TextBlock(text="성명", box=Box(x=20, y=60+i*50, width=70, height=25)) for i in range(3)]
        values = [TextBlock(text="가상 학생 이름", box=Box(x=600, y=60+i*50, width=250, height=25)) for i in range(3)]
        self.assertEqual([item for pair in zip(labels, values) for item in pair], ocr._reading_order([*labels, *values]))


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
        with patch.object(ocr, "_remove_rules", side_effect=lambda image: image), patch.object(ocr, "_skew_angle", return_value=0), patch.object(ocr, "_tesseract_lines", side_effect=[
            [line("ㅇㅁ", 20)], [], upright, [], [], [],
        ]) as recognize:
            result = ocr._tesseract(self.image)
        self.assertEqual(6, recognize.call_count)
        self.assertEqual([self.text, "두번째 줄입니다"], [b.text for b in result])
        self.assertEqual(Box(x=1460, y=60, width=40, height=700), result[0].box)
        self.assertEqual(Box(x=1380, y=60, width=40, height=300), result[1].box)

    def test_unreliable_rotations_do_not_replace_original(self):
        with patch.object(ocr, "_remove_rules", side_effect=lambda image: image), patch.object(ocr, "_skew_angle", return_value=0), patch.object(ocr, "_tesseract_lines", side_effect=[
            [line("읽을 수 있는 원문", 50)], [], [line("가짜", 30)], [], [], [],
        ]):
            result = ocr._tesseract(self.image)
        self.assertEqual("읽을 수 있는 원문", result[0].text)

    def test_quality_does_not_trust_title_without_body(self):
        title = TextBlock(text="개인정보 수집 이용 동의서", box=Box(x=1, y=1, width=200, height=20), confidence=96)
        unreadable = title.model_copy(update={"text": "오류 글자 조각 " * 12, "confidence": 20})
        self.assertTrue(ocr._needs_review([]))
        self.assertTrue(ocr._needs_review([title]))
        self.assertTrue(ocr._needs_review([title, unreadable]))
        body = title.model_copy(update={"text": "수집 목적은 행사 참가 확인이며 보유 기간은 행사 종료일까지입니다.", "confidence": 92,
                                        "box": Box(x=1, y=60, width=400, height=20)})
        self.assertFalse(ocr._needs_review([title, body]))

    def test_sparse_form_is_not_confused_with_fragmented_heading(self):
        labels = [TextBlock(text=t, confidence=93, box=Box(x=20, y=30+i*40, width=100, height=25))
                  for i, t in enumerate(("작품요약서", "팀명", "작품명", "참가자", "작품요약"))]
        self.assertFalse(ocr._needs_review(labels))
        heading = [b.model_copy(update={"box": Box(x=20+i*110, y=30+i, width=100, height=25)}) for i, b in enumerate(labels)]
        self.assertTrue(ocr._needs_review(heading))

    def test_distant_page_crop_preserves_marks_near_all_edges(self):
        image = Image.new("RGB", (1800, 1400), "#665544")
        draw = ImageDraw.Draw(image)
        draw.rectangle((650, 400, 1150, 1000), fill="white")
        for x, y in ((655, 410), (1130, 410), (655, 975), (1130, 975)):
            draw.rectangle((x, y, x+8, y+8), fill="black")
        cropped, (left, top) = ocr._page_crop(image, distant_only=True)
        self.assertLess(cropped.width, image.width // 2)
        for x, y in ((655, 410), (1130, 410), (655, 975), (1130, 975)):
            self.assertEqual((0, 0, 0), cropped.getpixel((x-left, y-top)))

    def test_white_text_on_dark_screen_is_not_cropped_as_paper(self):
        image = Image.new("RGB", (1000, 800), "#111111")
        draw = ImageDraw.Draw(image)
        for x in range(50, 900, 80):
            draw.rectangle((x, 60, x+40, 110), fill="white")
        cropped, offset = ocr._page_crop(image, distant_only=True)
        self.assertEqual((0, 0), offset)
        self.assertEqual(image.size, cropped.size)

    def test_symbols_are_not_text_but_legacy_results_remain_compatible(self):
        symbol = TextBlock(text="==~", confidence=90, box=Box(x=20, y=20, width=100, height=20))
        self.assertTrue(ocr._needs_review([symbol]))
        legacy = symbol.model_copy(update={"text": "이전 저장 결과", "confidence": None})
        self.assertFalse(ocr._needs_review([legacy]))

    def test_bright_part_of_shaded_paper_is_not_the_whole_page(self):
        image = Image.new("RGB", (1800, 1400), "#665544")
        draw = ImageDraw.Draw(image)
        draw.rectangle((600, 300, 1200, 1100), fill="#bbbbbb")
        draw.rectangle((900, 300, 1200, 1100), fill="white")
        cropped, offset = ocr._page_crop(image, distant_only=True)
        self.assertEqual(image.size, cropped.size)
        self.assertEqual((0, 0), offset)

    def test_sideways_text_does_not_look_like_one_heading(self):
        blocks = [TextBlock(text="서로 다른 본문 줄입니다", confidence=90,
                            box=Box(x=100+i*60, y=100, width=30, height=450)) for i in range(5)]
        self.assertFalse(ocr._needs_review(blocks))

    def test_recovered_blank_form_is_not_replaced_by_longer_graphics_noise(self):
        labels = [TextBlock(text=t, confidence=93, box=Box(x=20, y=30+i*40, width=100, height=25))
                  for i, t in enumerate(("작품요약서", "팀명", "작품명", "참가자", "작품요약"))]
        noise = TextBlock(text="가나다"*20, confidence=70, box=Box(x=20, y=5, width=600, height=20))
        unreadable = noise.model_copy(update={"confidence": 55})
        buffer = io.BytesIO()
        self.image.save(buffer, "PNG")
        with patch.object(ocr.config, "OCR_PROVIDER", "tesseract"), \
             patch.object(ocr, "_tesseract", return_value=[unreadable]), \
             patch.object(ocr, "_layout_recovery", side_effect=lambda image, adaptive=False: [noise] if adaptive else labels):
            result = ocr.recognize(buffer.getvalue())
        self.assertFalse(result.needs_review)
        self.assertEqual([b.text for b in labels], [b.text for b in result.lines])

    def test_many_weak_body_characters_require_review_despite_readable_lines(self):
        blocks = [TextBlock(text="본문 글자 "*15, confidence=conf,
                            box=Box(x=20, y=30+i*45, width=600, height=25))
                  for i, conf in enumerate((70, 70, 70, 45, 45))]
        self.assertTrue(ocr._needs_review(blocks))

    def test_fast_model_sparse_form_keeps_a_reliable_original_heading(self):
        fixture = json.loads((Path(__file__).parent / "fixtures/ocr_sparse_fast.json").read_text("utf-8"))
        def lines(key):
            return [ocr._Line(TextBlock(**b), b["confidence"]) for b in fixture[key]]
        original, candidate = lines("original"), lines("candidate")
        self.assertTrue(ocr._needs_review([b.block for b in original]))
        self.assertTrue(ocr._needs_review([b.block for b in candidate]))
        recovered = ocr._preserve_reliable_regions(candidate, original)
        self.assertTrue(ocr._recovery_improves(recovered, original))
        self.assertFalse(ocr._needs_review([b.block for b in recovered]))
        from app.services import doc_reader
        self.assertEqual("summary", doc_reader.CLASSIFIER.classify([b.block for b in recovered]).doc_type.value)

    def test_empty_recovery_cannot_promote_only_the_trusted_subset(self):
        original = [line("성명 연락처", 90, Box(x=20, y=30+i*40, width=100, height=25)) for i in range(4)]
        original.append(line("손상된 본문 "*20, 20))
        self.assertEqual([], ocr._preserve_reliable_regions([], original))

    def test_rejected_fine_rotation_keeps_original_geometry(self):
        with patch.object(ocr, "_skew_angle", return_value=12), patch.object(ocr, "_tesseract_lines", return_value=[line(self.text, 70)]):
            image, lines, angle = ocr._deskew(self.image.convert("L"), [line(self.text, 80)], None, 1)
        self.assertEqual(self.image.size, image.size)
        self.assertEqual(0, angle)
        self.assertEqual(80, lines[0].conf)

    def test_cleanup_cannot_replace_legible_title_with_many_weak_characters(self):
        original = [line("작품 요약서", 90)]
        candidate = [line("의미 없는 글자 " * 20, 60)]
        self.assertGreater(ocr._quality(candidate), ocr._quality(original) + 10)
        self.assertFalse(ocr._improves(candidate, original, 10))


if __name__ == "__main__":
    unittest.main()

"""Real HTTP/multipart integration checks; OCR and external AI are always mocked."""
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi import HTTPException, UploadFile
from fastapi.testclient import TestClient
from starlette.datastructures import UploadFile as MultipartUploadFile

from app.main import app
from app.models import RecognizedDocument
from app.routers import judge, uploads
from app.services import llm, ocr
from api_fixtures import image_bytes
from document_corpus import blocks


class ApiContractTest(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app, raise_server_exceptions=False)
        self.addCleanup(self.client.close)
        self.png = image_bytes()
        self.lines = blocks(["재직증명서\n성명: 김가상\n발급 기관: 예시회사"])
        self.recognize = self.enterContext(patch.object(ocr, "recognize", return_value=ocr.OcrResult(self.lines, 800, 1000)))
        self.enterContext(patch.object(llm, "available", return_value=False))
        self.ask_json = self.enterContext(patch.object(llm, "ask_json", side_effect=AssertionError("external AI disabled")))
        self.ask_image = self.enterContext(patch.object(llm, "ask_about_image", side_effect=AssertionError("external AI disabled")))

    def photo(self, data=None, content_type="application/octet-stream"):
        return ("page.png", self.png if data is None else data, content_type)

    def document(self):
        return {"doc_type": "certificate", "blocks": [line.model_dump() for line in self.lines],
                "pages": [{"width": 800, "height": 1000}], "fields": [], "needs_review": False}

    def assert_detail(self, response, status):
        self.assertEqual(status, response.status_code, response.text)
        self.assertIsInstance(response.json()["detail"], str)
        self.assertTrue(response.json()["detail"])

    def test_health_is_available(self):
        self.assertEqual({"ok": True}, self.client.get("/api/health").json())

    def test_read_accepts_flutter_octet_stream_and_returns_frontend_schema(self):
        response = self.client.post("/api/read", files={"photo": self.photo()})
        self.assertEqual(200, response.status_code, response.text)
        document = RecognizedDocument.model_validate(response.json())
        self.assertEqual("certificate", document.doc_type.value)
        self.assertEqual(800, document.pages[0].width)
        self.assertEqual(document.image_width, document.pages[0].width)
        self.assertEqual([0, 0, 0], [line.page for line in document.blocks])
        self.ask_json.assert_not_called()

    def test_read_multipart_preserves_page_order_and_dimensions(self):
        second = blocks(["성명: 이둘째"])
        self.recognize.side_effect = [ocr.OcrResult(self.lines, 800, 1000), ocr.OcrResult(second, 900, 1200)]
        response = self.client.post("/api/read", files=[("photo", self.photo()), ("photo", self.photo())])
        self.assertEqual(200, response.status_code, response.text)
        body = response.json()
        self.assertEqual([800, 900], [page["width"] for page in body["pages"]])
        self.assertEqual([0, 0, 0, 1], [line["page"] for line in body["blocks"]])

    def test_missing_photo_is_request_validation_error(self):
        for path in ("/api/read", "/api/write/check", "/api/sign/locate"):
            with self.subTest(path=path):
                response = self.client.post(path, data={"field": "성명"})
                self.assertEqual(422, response.status_code)
        self.recognize.assert_not_called()

    def test_empty_and_corrupt_uploads_are_client_errors_before_ocr(self):
        for data in (b"", b"not an image", self.png[:len(self.png) // 2]):
            for path in ("/api/read", "/api/write/check", "/api/sign/locate"):
                with self.subTest(path=path, data=data[:10]):
                    response = self.client.post(path, files={"photo": self.photo(data)}, data={"field": "성명"})
                    self.assert_detail(response, 400)
        self.recognize.assert_not_called()

    def test_oversized_single_photo_is_413_before_ocr(self):
        with patch.object(uploads, "MAX_PHOTO_BYTES", len(self.png) - 1):
            response = self.client.post("/api/read", files={"photo": self.photo()})
        self.assert_detail(response, 413)
        self.recognize.assert_not_called()

    def test_excess_page_count_is_413_before_ocr(self):
        with patch.object(uploads, "MAX_PAGES", 1):
            response = self.client.post("/api/read", files=[("photo", self.photo()), ("photo", self.photo())])
        self.assert_detail(response, 413)
        self.recognize.assert_not_called()

    def test_total_upload_size_is_bounded_before_any_page_is_recognized(self):
        with patch.object(uploads, "MAX_TOTAL_BYTES", len(self.png) * 2 - 1):
            response = self.client.post("/api/read", files=[("photo", self.photo()), ("photo", self.photo())])
        self.assert_detail(response, 413)
        self.recognize.assert_not_called()

    def test_invalid_later_page_closes_all_multipart_files_without_partial_ocr(self):
        closed = []
        original_close = MultipartUploadFile.close

        async def record_close(upload):
            await original_close(upload)
            closed.append(upload)

        with patch.object(MultipartUploadFile, "close", record_close):
            response = self.client.post("/api/read", files=[("photo", self.photo()), ("photo", self.photo(b"bad"))])
        self.assert_detail(response, 400)
        self.assertEqual(2, len({id(upload) for upload in closed}))
        self.assertTrue(all(upload.file.closed for upload in closed))
        self.recognize.assert_not_called()

    def test_provider_failure_is_502_without_internal_exception_content(self):
        self.recognize.side_effect = RuntimeError("secret-token at C:/private/provider.json")
        for path in ("/api/read", "/api/write/check"):
            with self.subTest(path=path):
                response = self.client.post(path, files={"photo": self.photo()}, data={"field": "성명"})
                self.assert_detail(response, 502)
                self.assertNotIn("secret-token", response.text)
                self.assertNotIn("provider.json", response.text)

    def test_read_review_gate_serializes_page_and_skips_ai(self):
        self.recognize.return_value = ocr.OcrResult(self.lines, 800, 1000, needs_review=True)
        with patch.object(llm, "available", return_value=True):
            response = self.client.post("/api/read", files={"photo": self.photo()})
        self.assertEqual(200, response.status_code)
        self.assertTrue(response.json()["needs_review"])
        self.assertEqual([0], response.json()["review_pages"])
        self.assertEqual([], response.json()["fields"])
        self.ask_json.assert_not_called()

    def test_write_unreadable_photo_is_422_and_skips_vision_ai(self):
        self.recognize.return_value = ocr.OcrResult(self.lines, 800, 1000, needs_review=True)
        with patch.object(llm, "available", return_value=True):
            response = self.client.post("/api/write/check", files={"photo": self.photo()}, data={"field": "성명"})
        self.assert_detail(response, 422)
        self.ask_image.assert_not_called()

    def test_write_rejects_blank_and_overlong_field_names(self):
        for field in ("   ", "가" * 81):
            with self.subTest(length=len(field)):
                response = self.client.post("/api/write/check", files={"photo": self.photo()}, data={"field": field})
                self.assert_detail(response, 422)
        self.recognize.assert_not_called()

    def test_write_valid_field_returns_expected_contract(self):
        response = self.client.post("/api/write/check", files={"photo": self.photo()}, data={"field": " 성명 "})
        self.assertEqual(200, response.status_code, response.text)
        self.assertEqual("성명", response.json()["field"])
        self.assertTrue(response.json()["found"])
        self.assertEqual("김가상", response.json()["written"])
        self.assertIsInstance(response.json()["box"], dict)

    def test_judge_valid_document_and_answers_reach_engine(self):
        payload = self.document() | {"answers": {"workers_5_plus": "yes"}}
        with patch.object(judge, "run_judge", return_value={"speech": "확인해 주세요.", "findings": []}) as engine:
            response = self.client.post("/api/judge", json=payload)
        self.assertEqual(200, response.status_code)
        self.assertEqual({"workers_5_plus": "yes"}, engine.call_args.args[1])
        self.assertEqual([], response.json()["findings"])

    def test_judge_rejects_empty_document_before_engine(self):
        with patch.object(judge, "run_judge") as engine:
            self.assert_detail(self.client.post("/api/judge", json={}), 422)
        engine.assert_not_called()

    def test_judge_review_flags_cannot_disagree_and_bypass_gate(self):
        with patch.object(judge, "run_judge") as engine:
            response = self.client.post("/api/judge", json=self.document() | {"needs_review": False, "review_pages": [0]})
        self.assert_detail(response, 422)
        engine.assert_not_called()

    def test_judge_rejects_invalid_page_and_line_references(self):
        for page in (-1, 1, 100):
            payload = self.document()
            payload["blocks"][0]["page"] = page
            with self.subTest(page=page):
                self.assert_detail(self.client.post("/api/judge", json=payload), 422)
        for line in (-2, len(self.lines)):
            with self.subTest(line=line):
                payload = self.document() | {"fields": [{"label": "성명", "value": "김가상", "line": line}]}
                self.assert_detail(self.client.post("/api/judge", json=payload), 422)

    def test_judge_rejects_invalid_geometry(self):
        for sizes in ({"width": 0, "height": 1000}, {"width": 800, "height": -1}):
            with self.subTest(sizes=sizes):
                self.assert_detail(self.client.post("/api/judge", json=self.document() | {"pages": [sizes]}), 422)
        for box in ({"x": -1, "y": 0, "width": 100, "height": 20},
                    {"x": 0, "y": 0, "width": 0, "height": 20},
                    {"x": 790, "y": 0, "width": 100, "height": 20}):
            payload = self.document()
            payload["blocks"][0]["box"] = box
            with self.subTest(box=box):
                self.assert_detail(self.client.post("/api/judge", json=payload), 422)

    def test_judge_keeps_legacy_single_page_and_unknown_field_line_compatible(self):
        payload = self.document() | {"pages": [], "image_width": 800, "image_height": 1000,
                                     "fields": [{"label": "성명", "value": "김가상", "line": -1}]}
        response = self.client.post("/api/judge", json=payload)
        self.assertEqual(200, response.status_code, response.text)

    def test_malformed_json_and_unknown_type_are_request_errors(self):
        self.assertEqual(422, self.client.post("/api/judge", content=b"{", headers={"Content-Type": "application/json"}).status_code)
        self.assertEqual(422, self.client.post("/api/judge", json=self.document() | {"doc_type": "made_up"}).status_code)


class UploadLifetimeTest(unittest.IsolatedAsyncioTestCase):
    async def test_unknown_size_upload_uses_bounded_read_and_closes_every_file(self):
        class RecordingFile(io.BytesIO):
            def read(self, size=-1):
                self.read_size = size
                return super().read(size)

        first_file = RecordingFile(b"x" * 100)
        other_file = io.BytesIO(image_bytes())
        photos = [UploadFile(file=first_file), UploadFile(file=other_file)]
        with patch.object(uploads, "MAX_PHOTO_BYTES", 8):
            with self.assertRaises(HTTPException) as raised:
                await uploads.read_images(photos)
        self.assertEqual(413, raised.exception.status_code)
        self.assertEqual(9, first_file.read_size)
        self.assertTrue(first_file.closed)
        self.assertTrue(other_file.closed)

    async def test_successful_upload_close_is_idempotent_for_framework_cleanup(self):
        photo = UploadFile(file=io.BytesIO(image_bytes()))
        self.assertEqual([image_bytes()], await uploads.read_images([photo]))
        self.assertTrue(photo.file.closed)
        await photo.close()


if __name__ == "__main__":
    unittest.main()

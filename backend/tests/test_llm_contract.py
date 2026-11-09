"""Provider failures must preserve the offline rule-based read/write paths."""
import io
import http.client
import json
import sys
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient

from app import config
from app.main import app
from app.services import llm, ocr
from api_fixtures import image_bytes
from document_corpus import blocks


class LlmContractTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(config, "GROQ_API_KEY", "synthetic-test-key"))

    def response(self, body):
        return self.enterContext(patch.object(llm.urllib.request, "urlopen", return_value=io.BytesIO(body)))

    def test_invalid_provider_responses_use_the_recoverable_error_type(self):
        for body in (b"<html>upstream unavailable</html>", b"{", b"null", b"[]",
                     b'{"choices":[]}', b'{"choices":[{}]}',
                     b'{"choices":[{"message":{"content":null}}]}',
                     b'{"choices":[{"message":{"content":[]}}]}',
                     b'{"choices":[{"message":{"content":""}}]}'):
            with self.subTest(body=body):
                with patch.object(llm.urllib.request, "urlopen", return_value=io.BytesIO(body)):
                    with self.assertRaises(llm.LlmError):
                        llm.ask_json("synthetic document")

    def test_json_answer_must_be_an_object(self):
        for content in ("[]", "null", '"answer"', "invalid JSON"):
            with self.subTest(content=content):
                with patch.object(llm, "_chat", return_value=content):
                    with self.assertRaises(llm.LlmError):
                        llm.ask_json("synthetic document")

    def test_read_and_write_fall_back_when_provider_response_is_broken(self):
        lines = blocks(["재직증명서\n성명: 김가상\n발급 기관: 예시회사"])
        with TestClient(app, raise_server_exceptions=False) as client, \
                patch.object(ocr, "recognize", return_value=ocr.OcrResult(lines, 800, 1000)), \
                patch.object(llm.urllib.request, "urlopen", side_effect=lambda *a, **k: io.BytesIO(b'{"choices":[]}')):
            for path in ("/api/read", "/api/write/check"):
                with self.subTest(path=path):
                    response = client.post(path, files={"photo": ("page.png", image_bytes())}, data={"field": "성명"})
                    self.assertEqual(200, response.status_code, response.text)
                    self.assertEqual("rules", response.json()["reader"])
                    self.assertIn("김가상", response.text)

    def test_provider_error_does_not_copy_document_or_key_into_exception(self):
        error = urllib.error.HTTPError(llm.URL, 503, "unavailable", {}, io.BytesIO(b"synthetic-private-document synthetic-test-key"))
        with patch.object(llm.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(llm.LlmError) as raised:
                llm.ask_json("synthetic document")
        self.assertNotIn("synthetic-private-document", str(raised.exception))
        self.assertNotIn("synthetic-test-key", str(raised.exception))
        self.assertTrue(error.fp.closed)

    def test_successful_provider_reply_is_preserved(self):
        body = {"choices": [{"message": {"content": '{"field":"김가상"}'}}]}
        opened = self.response(json.dumps(body, ensure_ascii=False).encode())
        self.assertEqual({"field": "김가상"}, llm.ask_json("synthetic document"))
        self.assertEqual(30, opened.call_args.kwargs["timeout"])

    def test_truncated_and_failed_connections_are_recoverable(self):
        failures = [TimeoutError(), ConnectionResetError(), urllib.error.URLError("synthetic failure"),
                    http.client.IncompleteRead(b"partial reply")]
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                with patch.object(llm.urllib.request, "urlopen", side_effect=failure):
                    with self.assertRaises(llm.LlmError):
                        llm.ask_json("synthetic document")

    def test_oversized_provider_reply_is_bounded_and_closed(self):
        reply = io.BytesIO(b"x" * 100)
        with patch.object(llm, "MAX_RESPONSE_BYTES", 10), \
                patch.object(llm.urllib.request, "urlopen", return_value=reply):
            with self.assertRaises(llm.LlmError):
                llm.ask_json("synthetic document")
        self.assertTrue(reply.closed)


if __name__ == "__main__":
    unittest.main()

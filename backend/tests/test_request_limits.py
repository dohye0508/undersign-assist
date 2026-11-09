"""Exercise real ASGI/multipart parsing, including interrupted disk spooling."""
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
from starlette import formparsers

from app.main import app
from app import request_limits
from app.routers import uploads
from app.services import llm, ocr
from api_fixtures import image_bytes
from document_corpus import blocks


class RequestLimitTest(unittest.IsolatedAsyncioTestCase):
    async def request(self, chunks, *, path="/api/read", headers=()):
        messages, calls = [], 0
        pending = iter(chunks)

        async def receive():
            nonlocal calls
            calls += 1
            data, more = next(pending)
            return {"type": "http.request", "body": data, "more_body": more}

        async def send(message):
            messages.append(message)

        scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
                 "method": "POST", "scheme": "http", "path": path, "raw_path": path.encode(),
                 "query_string": b"", "root_path": "", "headers": list(headers),
                 "client": ("test", 123), "server": ("test", 80)}
        await app(scope, receive, send)
        start = next(message for message in messages if message["type"] == "http.response.start")
        data = b"".join(message.get("body", b"") for message in messages if message["type"] == "http.response.body")
        return start["status"], json.loads(data), calls

    async def test_declared_oversize_is_rejected_without_receiving_body(self):
        for path in ("/api/read", "/api/read/", "/api/write/check", "/api/sign/locate", "/api/judge"):
            with self.subTest(path=path):
                status, body, reads = await self.request([], path=path, headers=[(b"content-length", b"999999999")])
                self.assertEqual(413, status)
                self.assertEqual(0, reads)
                self.assertEqual(request_limits.TOO_LARGE, body["detail"])

    async def test_malformed_or_ambiguous_lengths_are_rejected_before_reading(self):
        for lengths in ([b"-1"], [b"invalid"], [b"1", b"2"], [b""]):
            with self.subTest(lengths=lengths):
                status, _, reads = await self.request([], headers=[(b"content-length", length) for length in lengths])
                self.assertEqual(400, status)
                self.assertEqual(0, reads)

    async def test_huge_length_header_does_not_raise_integer_conversion_error(self):
        status, _, reads = await self.request([], headers=[(b"content-length", b"9" * 5000)])
        self.assertEqual(413, status)
        self.assertEqual(0, reads)

    async def test_chunked_or_underdeclared_upload_stops_and_removes_disk_spool(self):
        prefix = b'--sample\r\nContent-Disposition: form-data; name="photo"; filename="large.png"\r\nContent-Type: image/png\r\n\r\n'
        original_spool = formparsers.SpooledTemporaryFile
        for lengths in ([], [(b"content-length", b"1")]):
            files = []

            def spool(*args, **kwargs):
                file = original_spool(*args, **kwargs)
                files.append(file)
                return file

            with self.subTest(lengths=lengths), \
                    patch.object(formparsers, "SpooledTemporaryFile", side_effect=spool), \
                    patch.object(request_limits, "_request_limit", return_value=1200 * 1024), \
                    patch.object(ocr, "recognize") as recognize:
                status, body, reads = await self.request(
                    [(prefix + b"x" * (1100 * 1024), True), (b"y" * (200 * 1024), True),
                     (b"\r\n--sample--\r\n", False)],
                    headers=[(b"content-type", b"multipart/form-data; boundary=sample"), *lengths],
                )
                self.assertEqual(413, status)
                self.assertEqual(2, reads, "must not consume the rest of the oversized upload")
                self.assertEqual(request_limits.TOO_LARGE, body["detail"])
                self.assertEqual(1, len(files))
                self.assertTrue(files[0]._rolled, "exercise a real disk spool, not only BytesIO")
                self.assertTrue(files[0].closed)
                recognize.assert_not_called()

    async def test_chunked_json_is_bounded_before_judgement(self):
        with patch.object(request_limits, "MAX_JUDGE_BYTES", 20):
            status, body, reads = await self.request(
                [(b'{"full_text":"', True), (b"x" * 30, True), (b'"}', False)],
                path="/api/judge", headers=[(b"content-type", b"application/json")],
            )
        self.assertEqual(413, status)
        self.assertEqual(request_limits.TOO_LARGE, body["detail"])
        self.assertEqual(2, reads)

    def test_valid_multipart_overhead_is_not_counted_as_photo_bytes(self):
        photo = image_bytes()
        lines = blocks(["재직증명서\n성명: 김가상"])
        with TestClient(app) as client, \
                patch.object(uploads, "MAX_TOTAL_BYTES", len(photo)), \
                patch.object(ocr, "recognize", return_value=ocr.OcrResult(lines, 800, 1000)), \
                patch.object(llm, "available", return_value=False):
            response = client.post("/api/read", files={"photo": ("가상 문서.png", photo)}, data={"unused": "metadata"})
        self.assertEqual(200, response.status_code, response.text)

    def test_early_413_keeps_browser_cors_headers(self):
        with TestClient(app) as client:
            response = client.post("/api/read", content=b"", headers={
                "Content-Length": str(100 * 1024 * 1024), "Origin": "https://dohye0508.github.io"})
        self.assertEqual(413, response.status_code)
        self.assertEqual("*", response.headers["access-control-allow-origin"])


if __name__ == "__main__":
    unittest.main()

"""Stop oversized bodies while receiving them, before multipart spooling grows."""

from starlette.formparsers import MultiPartException
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.routers import uploads

FORM_OVERHEAD_BYTES = 1024 * 1024  # Multipart boundaries, filenames and form fields.
MAX_JUDGE_BYTES = 2 * 1024 * 1024
TOO_LARGE = "요청 크기가 너무 커요. 사진 크기나 장수를 줄여 다시 보내 주세요."


def _request_limit(path: str) -> int | None:
    path = path.rstrip("/")
    if path == "/api/read":
        return uploads.MAX_TOTAL_BYTES + FORM_OVERHEAD_BYTES
    if path in ("/api/write/check", "/api/sign/locate"):
        return uploads.MAX_PHOTO_BYTES + FORM_OVERHEAD_BYTES
    if path == "/api/judge":
        return MAX_JUDGE_BYTES
    return None


class RequestSizeLimitMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        limit = _request_limit(scope.get("path", ""))
        if scope["type"] != "http" or scope.get("method") != "POST" or limit is None:
            await self.app(scope, receive, send)
            return

        lengths = [value for name, value in scope["headers"] if name.lower() == b"content-length"]
        if lengths:
            # Reject malformed/ambiguous metadata, but also count actual bytes:
            # Content-Length is absent for chunked uploads and cannot be trusted.
            if len(lengths) != 1 or not lengths[0].isdigit():
                await JSONResponse({"detail": "요청 크기 정보가 올바르지 않아요."}, status_code=400)(scope, receive, send)
                return
            declared = lengths[0].lstrip(b"0") or b"0"
            if len(declared) > len(str(limit)) or int(declared) > limit:
                await JSONResponse({"detail": TOO_LARGE}, status_code=413)(scope, receive, send)
                return

        received = 0
        exceeded = False
        replied = False

        async def limited_receive() -> Message:
            nonlocal received, exceeded
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    exceeded = True
                    # Starlette closes multipart temporary files on this exception,
                    # including versions that do not catch arbitrary stream errors.
                    raise MultiPartException(TOO_LARGE)
            return message

        async def limited_send(message: Message) -> None:
            nonlocal replied
            if exceeded:
                # Form parsing normally maps MultiPartException to HTTP 400.
                # Keep its cleanup, but return our specific, safe 413 response.
                if not replied:
                    replied = True
                    await JSONResponse({"detail": TOO_LARGE}, status_code=413)(scope, receive, send)
                return
            await send(message)

        await self.app(scope, limited_receive, limited_send)

"""Small valid upload bytes for route tests; OCR remains mocked."""
import io

from PIL import Image


def image_bytes() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (40, 40), "white").save(buffer, format="PNG")
    return buffer.getvalue()

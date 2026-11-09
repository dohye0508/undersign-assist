"""Bound and validate uploaded images, and release every multipart spool."""

import asyncio
import io
import warnings

from fastapi import HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError

MAX_PHOTO_BYTES = 10 * 1024 * 1024
MAX_TOTAL_BYTES = 50 * 1024 * 1024
MAX_PAGES = 10


def _validate_image(data: bytes, page: int) -> None:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                image.load()
    except (Image.DecompressionBombWarning, Image.DecompressionBombError) as error:
        raise HTTPException(413, f"{page}페이지 사진의 해상도가 너무 커요. 크기를 줄여 주세요.") from error
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as error:
        raise HTTPException(400, f"{page}페이지 사진을 열 수 없어요. 정상적인 사진 파일을 다시 선택해 주세요.") from error


async def read_images(photos: list[UploadFile]) -> list[bytes]:
    """Validate the complete batch before OCR; never leave later files open on failure."""
    try:
        if not photos:
            raise HTTPException(400, "문서 사진을 한 장 이상 보내 주세요.")
        if len(photos) > MAX_PAGES:
            raise HTTPException(413, f"사진은 한 번에 {MAX_PAGES}페이지까지 보내 주세요.")
        images, total = [], 0
        for page, photo in enumerate(photos, start=1):
            if photo.size is not None and photo.size > MAX_PHOTO_BYTES:
                raise HTTPException(413, f"{page}페이지 사진이 너무 커요. 사진 한 장은 10MB 이하로 보내 주세요.")
            data = await photo.read(MAX_PHOTO_BYTES + 1)
            if len(data) > MAX_PHOTO_BYTES:
                raise HTTPException(413, f"{page}페이지 사진이 너무 커요. 사진 한 장은 10MB 이하로 보내 주세요.")
            if not data:
                raise HTTPException(400, f"{page}페이지 사진 파일이 비어 있어요. 다시 선택해 주세요.")
            total += len(data)
            if total > MAX_TOTAL_BYTES:
                raise HTTPException(413, "사진 전체 크기는 50MB 이하로 보내 주세요.")
            await asyncio.to_thread(_validate_image, data, page)
            images.append(data)
        return images
    finally:
        for photo in photos:
            await photo.close()

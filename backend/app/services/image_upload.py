"""
Shared upload validation for every image endpoint.

- Size cap (MAX_FILE_SIZE_MB)
- Real type check by decoding with Pillow (JPEG, PNG, WebP, HEIC/HEIF only)
- Applies EXIF orientation, then drops ALL metadata (GPS, device, timestamps)
- Downscales to MAX_SIDE on the long edge and re-encodes as JPEG
"""
from __future__ import annotations

import io

from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps

from app.core.config import settings

try:  # HEIC support (iPhone photos)
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:  # pragma: no cover
    pass

Image.MAX_IMAGE_PIXELS = 60_000_000  # decompression bomb guard
MAX_SIDE = 2048
_ALLOWED = {"JPEG", "PNG", "WEBP", "HEIF", "HEIC", "MPO"}


async def read_clean_image(upload: UploadFile) -> bytes:
    max_bytes = settings.MAX_FILE_SIZE_MB * 1024 * 1024
    data = await upload.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(status_code=413, detail=f"That photo is too big. Please keep it under {settings.MAX_FILE_SIZE_MB} MB.")
    return clean_image_bytes(data)


def clean_image_bytes(data: bytes) -> bytes:
    try:
        img = Image.open(io.BytesIO(data))
        fmt = (img.format or "").upper()
        if fmt not in _ALLOWED:
            raise ValueError(fmt)
        img.load()
    except Exception:
        raise HTTPException(status_code=415, detail="Please upload a JPEG, PNG, WebP or HEIC photo.")

    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "L"):
        bg = Image.new("RGB", img.size, (255, 255, 255))
        rgba = img.convert("RGBA")
        bg.paste(rgba, mask=rgba.split()[-1])
        img = bg
    elif img.mode == "L":
        img = img.convert("RGB")
    img.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)

    out = io.BytesIO()
    img.save(out, format="JPEG", quality=90, optimize=True)  # no exif= → metadata dropped
    return out.getvalue()

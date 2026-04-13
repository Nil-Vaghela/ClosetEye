"""
Body Model Service
==================
Processes a user's reference photo into an enhanced body image used as the
base for all virtual try-on.

Pipeline
--------
1. Auto-rotate from EXIF (fixes upside-down phone photos)
2. Validate: check image is taller than wide (portrait / full-body)
3. Auto-enhance: levels, sharpening, white-balance
4. Remove background with rembg (U²-Net, runs locally)
5. Return PNG with transparent background

The output is saved as both the silhouette (for display) and the raw
body_photo_url (used by try-on service, which does its own resize).
"""
from __future__ import annotations

import io
import logging
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

logger = logging.getLogger(__name__)


def generate_silhouette(image_bytes: bytes) -> bytes:
    """
    Process a body photo into a high-quality cutout for virtual try-on.

    Args:
        image_bytes: raw image bytes (JPEG, PNG, WEBP, HEIC)

    Returns:
        PNG bytes with transparent background (RGBA)

    Raises:
        RuntimeError: with a user-friendly message if processing fails
    """
    try:
        from rembg import remove as rembg_remove
    except ImportError:
        raise RuntimeError("rembg is not installed. Run: pip install rembg onnxruntime")

    # ── 1. Load and auto-orient ─────────────────────────────────────────────
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        img = ImageOps.exif_transpose(img)   # fix phone rotation
    except Exception as exc:
        raise RuntimeError(f"Could not open image: {exc}") from exc

    w, h = img.size
    logger.info(f"Body photo loaded: {w}x{h}")

    # ── 2. Soft validation (warn, don't block) ──────────────────────────────
    if w > h:
        logger.warning(
            "Body photo appears to be landscape orientation. "
            "Try-on quality is best with a full-body portrait photo."
        )
    if max(w, h) < 400:
        logger.warning("Body photo resolution is very low (<400px). Results may be blurry.")

    # ── 3. Auto-enhance before background removal ───────────────────────────
    # Better contrast and sharpness helps rembg produce cleaner edges
    img = _auto_enhance(img)

    # ── 4. Upscale small photos to at least 768px wide for better segmentation
    min_w = 768
    if w < min_w:
        scale = min_w / w
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
        logger.info(f"Upscaled body photo: {w}x{h} → {img.size[0]}x{img.size[1]}")

    # ── 5. Remove background ─────────────────────────────────────────────────
    logger.info("Running rembg background removal...")
    enhanced_bytes = _to_jpeg(img)
    output_bytes = rembg_remove(enhanced_bytes)

    # ── 6. Open result, clean up, add small padding ──────────────────────────
    result = Image.open(io.BytesIO(output_bytes)).convert("RGBA")
    result = _clean_and_pad(result)

    # ── 7. Encode as PNG ──────────────────────────────────────────────────────
    out = io.BytesIO()
    result.save(out, format="PNG", optimize=True)
    logger.info(f"Silhouette generated: {out.tell()} bytes, size {result.size}")
    return out.getvalue()


# ── Helpers ────────────────────────────────────────────────────────────────────

def _auto_enhance(img: Image.Image) -> Image.Image:
    """
    Apply gentle auto-enhancement to improve rembg segmentation quality.
    - Sharpening: helps rembg find crisp body edges
    - Contrast:   separates person from background
    - Auto-levels: normalises over/underexposed phone photos
    """
    # Auto-levels: stretch the histogram to use full 0-255 range
    img_np = _pil_auto_levels(img)

    # Sharpening (moderate — we don't want artefacts)
    img_np = ImageEnhance.Sharpness(img_np).enhance(1.5)

    # Slight contrast boost
    img_np = ImageEnhance.Contrast(img_np).enhance(1.10)

    return img_np


def _pil_auto_levels(img: Image.Image) -> Image.Image:
    """
    Stretch each channel to [0, 255] independently (auto white balance).
    Fixes dark/overexposed photos that confuse rembg.
    """
    import numpy as np
    arr = np.array(img, dtype=np.float32)
    for c in range(3):
        ch = arr[:, :, c]
        lo, hi = np.percentile(ch, 1), np.percentile(ch, 99)
        if hi > lo:
            arr[:, :, c] = np.clip((ch - lo) / (hi - lo) * 255, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def _clean_and_pad(img: Image.Image, pad_pct: float = 0.04) -> Image.Image:
    """
    Crop to bounding box and add small padding so body isn't clipped at edges.
    """
    bbox = img.getbbox()
    if not bbox:
        return img

    cw, ch = img.size
    pad_x = int((bbox[2] - bbox[0]) * pad_pct)
    pad_y = int((bbox[3] - bbox[1]) * pad_pct)
    bbox = (
        max(0, bbox[0] - pad_x),
        max(0, bbox[1] - pad_y),
        min(cw, bbox[2] + pad_x),
        min(ch, bbox[3] + pad_y),
    )
    return img.crop(bbox)


def _to_jpeg(img: Image.Image, quality: int = 95) -> bytes:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def save_upload(data: bytes, dest: Path) -> None:
    """Write bytes to disk, creating parent directories as needed."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)

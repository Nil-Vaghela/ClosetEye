"""
Garment Service
===============
Pipeline for extracting and processing clothing images:
1. Photo type detection (WORN vs FLATLAY heuristic)
2. Background removal via rembg
3. Dewrinkle/cleanup via PIL image filters
4. Multi-item extraction: isolate person → crop by body zone → white bg
"""
from __future__ import annotations

import io
import logging
from enum import Enum as PyEnum

from PIL import Image, ImageFilter, ImageEnhance

logger = logging.getLogger(__name__)


class PhotoType(str, PyEnum):
    """Type of clothing photo."""
    WORN = "worn"
    FLATLAY = "flatlay"


# ── rembg wrapper (lazy import) ────────────────────────────────────────────

def _rembg_remove(data: bytes) -> bytes:
    """Lazy-import rembg and remove background. Raises ImportError/RuntimeError."""
    from rembg import remove as rembg_remove
    return rembg_remove(data)


# ── Photo type detection ───────────────────────────────────────────────────

def detect_photo_type_heuristic(image_bytes: bytes) -> PhotoType:
    try:
        removed = _rembg_remove(image_bytes)
        img = Image.open(io.BytesIO(removed)).convert("RGBA")
        bbox = img.getbbox()
        if not bbox:
            return PhotoType.FLATLAY
        x0, y0, x1, y1 = bbox
        ratio = (y1 - y0) / max(1, x1 - x0)
        return PhotoType.WORN if ratio > 1.5 else PhotoType.FLATLAY
    except Exception:
        return PhotoType.FLATLAY


# ── Single-item garment extraction ─────────────────────────────────────────

def extract_garment(image_bytes: bytes, photo_type: PhotoType = None) -> bytes:
    """Remove background, tight-crop with 3 % padding, return PNG."""
    removed = _rembg_remove(image_bytes)
    img = Image.open(io.BytesIO(removed)).convert("RGBA")
    bbox = img.getbbox()
    if bbox:
        x0, y0, x1, y1 = bbox
        w, h = x1 - x0, y1 - y0
        px, py = int(w * 0.03), int(h * 0.03)
        iw, ih = img.size
        img = img.crop((
            max(0, x0 - px), max(0, y0 - py),
            min(iw, x1 + px), min(ih, y1 + py),
        ))
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


# ── Multi-item extraction helpers ──────────────────────────────────────────

def isolate_person(image_bytes: bytes) -> Image.Image:
    """
    rembg on the FULL photo → RGBA image with background transparent.
    Returns the full-size image (NOT tight-cropped) so pixel positions
    stay consistent with the original photo.
    """
    try:
        removed = _rembg_remove(image_bytes)
        return Image.open(io.BytesIO(removed)).convert("RGBA")
    except Exception as exc:
        logger.warning(f"rembg failed: {exc}; returning original")
        return Image.open(io.BytesIO(image_bytes)).convert("RGBA")


# Category → (top%, bottom%) of the person's tight bounding box.
# Percentages are relative to person height (from rembg getbbox).
# Designed for full-body standing photos — skip head (~14%) for tops.
_CATEGORY_ZONES_PERSON: dict[str, tuple[float, float]] = {
    "top":       (0.14, 0.60),  # skip head (~14 % of body), take torso
    "outerwear": (0.10, 0.65),
    "bottom":    (0.46, 0.98),
    "dress":     (0.12, 0.95),
    "shoes":     (0.87, 1.00),
    "accessory": (0.00, 0.22),
    "other":     (0.10, 0.95),
}

# Product shot background: warm off-white matching reference app
_PRODUCT_BG = (240, 238, 234)


def _place_on_product_bg(rgba: Image.Image, target: int = 800) -> Image.Image:
    """
    Place an RGBA garment on a warm off-white product background,
    centered with comfortable padding — clean e-commerce product shot.
    """
    bbox = rgba.getbbox()
    if bbox:
        rgba = rgba.crop(bbox)

    w, h = rgba.size
    if w == 0 or h == 0:
        return Image.new("RGB", (target, target), _PRODUCT_BG)

    inner = int(target * 0.76)
    scale = min(inner / w, inner / h)
    new_w = int(w * scale)
    new_h = int(h * scale)
    rgba = rgba.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (target, target), (*_PRODUCT_BG, 255))
    x = (target - new_w) // 2
    y = (target - new_h) // 2
    canvas.paste(rgba, (x, y), rgba)

    rgb = Image.new("RGB", (target, target), _PRODUCT_BG)
    rgb.paste(canvas, mask=canvas.split()[3])
    return rgb


# Keep legacy alias used by single-item upload path
def _place_on_white_square(rgba: Image.Image, target: int = 800) -> Image.Image:
    return _place_on_product_bg(rgba, target)


def extract_product_image_for_category(
    image_bytes: bytes,
    category: str,
) -> bytes:
    """
    Extract a clean product image of a specific garment from an outfit photo.

    Pipeline:
    1. Standard rembg (u2net) — removes photo background, isolates person.
       Works reliably on real-world photos (outdoor, indoor, any background).
    2. Person-relative zone crop — skips head for tops, lower body for bottoms.
    3. Place on warm product background.

    Result: the REAL garment as worn, cleanly framed.
    Real fabric, real colour, real texture — no AI generation, no artifacts.
    """
    isolated = isolate_person(image_bytes)
    return crop_item_by_category(isolated, category)


def crop_item_by_category(
    isolated_person: Image.Image,
    category: str,
) -> bytes:
    """
    Crop a clothing item from an already-isolated person image using
    category-based body zones, then place on a clean product background.

    Returns PNG bytes — professional product-shot look.
    """
    person_bbox = isolated_person.getbbox()
    if not person_bbox:
        canvas = Image.new("RGB", (800, 800), _PRODUCT_BG)
        buf = io.BytesIO()
        canvas.save(buf, format="PNG")
        return buf.getvalue()

    px0, py0, px1, py1 = person_bbox
    person_h = py1 - py0
    person_w = px1 - px0

    top_pct, bottom_pct = _CATEGORY_ZONES_PERSON.get(
        category.lower(), _CATEGORY_ZONES_PERSON["other"]
    )

    crop_top = int(py0 + person_h * top_pct)
    crop_bottom = int(py0 + person_h * bottom_pct)

    # Horizontal: full person width + 6 % pad
    h_pad = int(person_w * 0.06)
    crop_left = max(0, px0 - h_pad)
    crop_right = min(isolated_person.width, px1 + h_pad)

    cropped = isolated_person.crop((crop_left, crop_top, crop_right, crop_bottom))

    # Place on product background
    final = _place_on_product_bg(cropped, target=800)

    logger.info(
        f"person-zone '{category}' {top_pct:.0%}-{bottom_pct:.0%} → "
        f"crop ({crop_left},{crop_top})-({crop_right},{crop_bottom}), "
        f"final {final.size}"
    )

    buf = io.BytesIO()
    final.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


# Keep legacy function signature for backward compat
def crop_item_from_photo(
    image_bytes: bytes,
    bbox: dict,
    padding_pct: float = 0.08,
) -> bytes:
    """Legacy bbox-based crop. Prefer isolate_person + crop_item_by_category."""
    img = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    w, h = img.size
    top = int(h * max(0, bbox.get("top", 0)) / 100)
    left = int(w * max(0, bbox.get("left", 0)) / 100)
    bottom = int(h * min(100, bbox.get("bottom", 100)) / 100)
    right = int(w * min(100, bbox.get("right", 100)) / 100)
    pad_x = int((right - left) * padding_pct)
    pad_y = int((bottom - top) * padding_pct)
    cropped = img.crop((
        max(0, left - pad_x), max(0, top - pad_y),
        min(w, right + pad_x), min(h, bottom + pad_y),
    ))
    final = _place_on_white_square(cropped, target=800)
    buf = io.BytesIO()
    final.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


# ── Dewrinkle / cleanup ───────────────────────────────────────────────────

def dewrinkle_and_clean(image_bytes: bytes) -> bytes:
    """
    Sharpen + contrast boost.  Preserves alpha if present.
    """
    try:
        img = Image.open(io.BytesIO(image_bytes))
        has_alpha = img.mode == "RGBA"

        if has_alpha:
            alpha = img.split()[3]
            rgb = Image.new("RGB", img.size, (255, 255, 255))
            rgb.paste(img, mask=alpha)
        else:
            rgb = img.convert("RGB")
            alpha = None

        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1, percent=120, threshold=3))
        rgb = ImageEnhance.Contrast(rgb).enhance(1.08)

        if has_alpha and alpha is not None:
            out_img = rgb.convert("RGBA")
            out_img.putalpha(alpha)
        else:
            out_img = rgb

        buf = io.BytesIO()
        out_img.save(buf, format="PNG", optimize=True)
        return buf.getvalue()
    except Exception as exc:
        logger.error(f"Image cleaning failed: {exc}")
        return image_bytes  # return original rather than crash

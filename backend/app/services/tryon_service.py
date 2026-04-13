"""
Try-On Service
==============
PRIMARY:  gpt-image-1 mask-based inpainting
  1. Detect clothing zone on body photo (zone percentages same as garment extractor)
  2. Make that zone transparent → PNG with alpha
  3. POST [body_png, garment_png] + prompt to gpt-image-1 images.edit
  4. gpt-image-1 paints the garment into the transparent zone photorealistically

FALLBACK: IDM-VTON via Replicate (if OpenAI key unavailable)

Multi-garment: process bottom first, then top, chain results.
Face restoration: paste original sharp face back after each step.
"""
from __future__ import annotations

import asyncio
import base64
import io
import logging
import os
from functools import partial

import cv2
import numpy as np
import httpx
from PIL import Image, ImageFilter
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.clothing import ClothingItem
from app.core.config import settings

logger = logging.getLogger(__name__)

# ── Zone definitions (fraction of body-photo height) ──────────────────────────
# Must stay in sync with garment_service._CATEGORY_ZONES_PERSON
_ZONE: dict[str, tuple[float, float]] = {
    "top":       (0.14, 0.62),
    "outerwear": (0.10, 0.68),
    "bottom":    (0.44, 1.00),
    "dress":     (0.12, 0.98),
    "shoes":     (0.82, 1.00),
    "accessory": (0.00, 0.24),
    "other":     (0.10, 0.95),
}

# Sort order for layering (process bottom first so top can cover waistband)
_LAYER_ORDER = {"bottom": 0, "shoes": 1, "dress": 2, "top": 3, "outerwear": 4}

# IDM-VTON category mapping: our categories → IDM-VTON's expected values
# NOTE: "shoes" and "accessory" are intentionally excluded — IDM-VTON only
#       supports upper_body / lower_body / dresses. Running a shoe image through
#       lower_body OVERWRITES correctly-placed pants with the shoe reference,
#       producing the washed-out / wrong-colour pants bug.
_IDM_CATEGORY = {
    "top":       "upper_body",
    "outerwear": "upper_body",
    "bottom":    "lower_body",
    "dress":     "dresses",
    "other":     "upper_body",
}

# Categories that IDM-VTON genuinely supports (all others are skipped for IDM)
_IDM_SUPPORTED = {"top", "outerwear", "bottom", "dress", "other"}

# IDM-VTON fallback versions
_IDM_VERSIONS = [
    "cuuupid/idm-vton:0513734a452173b8173e907e3a59d19a36266e55b48528559432bd21c7d7e985",
    "cuuupid/idm-vton:906425dbca90663ff5427624839572cc56ea7d380343d13e2a4c4b09d3f0c30f",
]


# ── Image helpers ──────────────────────────────────────────────────────────────

def _to_jpeg(image_bytes: bytes, max_dim: int = 1024) -> bytes:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img = _auto_orient(img)
    w, h = img.size
    if max(w, h) > max_dim:
        scale = max_dim / max(w, h)
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


def _auto_orient(img: "Image.Image") -> "Image.Image":
    """Rotate image according to EXIF orientation tag so it's always upright."""
    try:
        from PIL import ImageOps
        return ImageOps.exif_transpose(img)
    except Exception:
        return img


# IDM-VTON native resolution (VITON-HD training size)
_IDM_W, _IDM_H = 768, 1024


def _prepare_body_for_idm(body_bytes: bytes) -> bytes:
    """
    Resize and pad the body photo to exactly 768×1024 — the resolution
    IDM-VTON was trained on (VITON-HD). Wrong sizes cause misaligned clothing.

    Steps:
    1. Auto-rotate from EXIF (fixes upside-down phone photos)
    2. Scale to fit within 768×1024, preserving aspect ratio
    3. Pad with white to reach exactly 768×1024
    4. Mild sharpening + contrast boost to improve segmentation quality
    """
    img = Image.open(io.BytesIO(body_bytes)).convert("RGB")
    img = _auto_orient(img)

    # Scale to fit, maintaining aspect ratio
    w, h = img.size
    scale = min(_IDM_W / w, _IDM_H / h)
    new_w, new_h = int(w * scale), int(h * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # Center on white canvas
    canvas = Image.new("RGB", (_IDM_W, _IDM_H), (255, 255, 255))
    canvas.paste(img, ((_IDM_W - new_w) // 2, (_IDM_H - new_h) // 2))

    # Enhance for better AI segmentation
    from PIL import ImageEnhance
    canvas = ImageEnhance.Sharpness(canvas).enhance(1.4)
    canvas = ImageEnhance.Contrast(canvas).enhance(1.08)

    buf = io.BytesIO()
    canvas.save(buf, format="JPEG", quality=95)
    logger.info(f"Body preprocessed: {w}x{h} → {new_w}x{new_h} → {_IDM_W}x{_IDM_H}")
    return buf.getvalue()


def _prepare_garment_for_idm(garment_bytes: bytes) -> bytes:
    """
    Place the garment flat on a pure-white 768×1024 canvas — exactly how
    IDM-VTON's training data was formatted. Transparent backgrounds become white.

    Steps:
    1. Convert to RGBA to preserve transparency
    2. Crop to tight bounding box (remove empty space)
    3. Scale to fill ~85% of the canvas with margin
    4. Composite onto white background
    """
    img = Image.open(io.BytesIO(garment_bytes)).convert("RGBA")

    # Crop tight to content
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    # Scale to fill 85% of canvas with margin
    w, h = img.size
    scale = min((_IDM_W * 0.85) / w, (_IDM_H * 0.85) / h)
    new_w, new_h = int(w * scale), int(h * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # Composite onto white canvas
    canvas = Image.new("RGBA", (_IDM_W, _IDM_H), (255, 255, 255, 255))
    canvas.paste(img, ((_IDM_W - new_w) // 2, (_IDM_H - new_h) // 2), img)

    buf = io.BytesIO()
    canvas.convert("RGB").save(buf, format="JPEG", quality=95)
    logger.info(f"Garment preprocessed: {w}x{h} → {new_w}x{new_h} → {_IDM_W}x{_IDM_H}")
    return buf.getvalue()


def _make_inpaint_png(body_bytes: bytes, category: str, max_dim: int = 1024) -> bytes:
    """
    Resize body photo and punch a transparent hole in the clothing zone.
    gpt-image-1 fills transparent pixels during inpainting.
    Returns PNG bytes.
    Uses numpy for vectorized alpha manipulation (100x faster than pixel loop).
    """
    img = Image.open(io.BytesIO(body_bytes)).convert("RGBA")
    w, h = img.size

    # Resize so longest edge = max_dim (gpt-image-1 needs square or near-square)
    if max(w, h) > max_dim:
        scale = max_dim / max(w, h)
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
        w, h = img.size

    top_frac, bot_frac = _ZONE.get(category, (0.10, 0.95))
    y1 = int(h * top_frac)
    y2 = min(int(h * bot_frac), h)

    # Numpy-based vectorized alpha zeroing (replaces 1M+ Python loop iterations)
    arr = np.array(img)
    arr[y1:y2, :, 3] = 0  # full zone transparent

    # Feather edges over 20px gradient
    feather = 20
    for i in range(feather):
        alpha_val = int(255 * i / feather)
        if y1 + i < h:
            arr[y1 + i, :, 3] = alpha_val
        if y2 - 1 - i >= 0:
            arr[y2 - 1 - i, :, 3] = alpha_val

    img = Image.fromarray(arr)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _garment_to_png(garment_bytes: bytes, max_dim: int = 768) -> bytes:
    """Convert garment image to PNG, resized."""
    img = Image.open(io.BytesIO(garment_bytes)).convert("RGBA")
    w, h = img.size
    if max(w, h) > max_dim:
        scale = max_dim / max(w, h)
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


# ── Face restoration (paste sharp face from original onto result) ─────────────

def _restore_face(original_bytes: bytes, result_bytes: bytes) -> bytes:
    """
    Paste the original sharp face back onto the AI result.

    Improvements over old version:
    - Tries multiple Haar cascade scales + LBP cascade as backup
    - Falls back to a fixed top-20% head region when no face is detected
      (covers the body-photo case where face is always near the top)
    - Much larger padding (60% sides, 100% top) so hair/ears are included
    - Larger Gaussian blend kernel so the seam is invisible
    """
    orig_np   = cv2.imdecode(np.frombuffer(original_bytes, np.uint8), cv2.IMREAD_COLOR)
    result_np = cv2.imdecode(np.frombuffer(result_bytes,   np.uint8), cv2.IMREAD_COLOR)
    if orig_np is None or result_np is None:
        return result_bytes

    oh, ow = orig_np.shape[:2]
    rh, rw = result_np.shape[:2]

    # ── Detect face in original ─────────────────────────────────────────────
    face_box = None

    # Try frontal face cascade at multiple scales
    for cascade_name in [
        "haarcascade_frontalface_default.xml",
        "haarcascade_frontalface_alt2.xml",
        "lbpcascade_frontalface_improved.xml",
    ]:
        path = cv2.data.haarcascades + cascade_name
        cascade = cv2.CascadeClassifier(path)
        if cascade.empty():
            continue
        gray = cv2.cvtColor(orig_np, cv2.COLOR_BGR2GRAY)
        faces = cascade.detectMultiScale(
            gray,
            scaleFactor=1.05,   # finer scale steps
            minNeighbors=4,
            minSize=(int(ow * 0.04), int(oh * 0.04)),
        )
        if len(faces) > 0:
            face_box = max(faces, key=lambda f: f[2] * f[3])
            break

    if face_box is not None:
        x, y, w, h = face_box
        # Generous padding: include full head, hair, neck
        pad_x   = int(w * 0.60)
        pad_top = int(h * 1.00)   # 100% — full hair on top
        pad_bot = int(h * 0.40)   # chin + upper neck
        x1 = max(0, x - pad_x);      y1 = max(0, y - pad_top)
        x2 = min(ow, x + w + pad_x); y2 = min(oh, y + h + pad_bot)
    else:
        # Fallback: assume head is in top 22% of body photo
        logger.info("No face detected — using fallback head region (top 22%)")
        x1, y1 = 0, 0
        x2, y2 = ow, int(oh * 0.22)

    # ── Scale the head region to result dimensions ──────────────────────────
    sx, sy = rw / ow, rh / oh
    rx1, ry1 = int(x1 * sx), int(y1 * sy)
    rx2, ry2 = int(x2 * sx), int(y2 * sy)
    fw, fh = rx2 - rx1, ry2 - ry1
    if fw <= 0 or fh <= 0:
        return result_bytes

    # Resize original head region to match result dimensions
    head_orig    = orig_np[y1:y2, x1:x2]
    head_resized = cv2.resize(head_orig, (fw, fh), interpolation=cv2.INTER_LANCZOS4)

    # ── Soft elliptical mask — large kernel so the seam disappears ──────────
    mask = np.zeros((fh, fw), dtype=np.float32)
    cx   = fw // 2
    cy   = int(fh * 0.42)
    ax   = int(fw * 0.48)   # horizontal semi-axis
    ay   = int(fh * 0.50)   # vertical semi-axis (taller to include hair)
    cv2.ellipse(mask, (cx, cy), (ax, ay), 0, 0, 360, 1.0, -1)

    # Blur radius = ~35% of the smaller dimension for a seamless blend
    ksize = max(5, (min(fw, fh) // 3) | 1)   # must be odd
    mask = cv2.GaussianBlur(mask, (ksize, ksize), 0)[:, :, np.newaxis]

    # ── Blend ────────────────────────────────────────────────────────────────
    out = result_np.copy().astype(np.float32)
    roi = out[ry1:ry2, rx1:rx2]
    out[ry1:ry2, rx1:rx2] = (
        head_resized.astype(np.float32) * mask +
        roi * (1.0 - mask)
    )
    out = np.clip(out, 0, 255).astype(np.uint8)
    ok, buf = cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, 95])
    return buf.tobytes() if ok else result_bytes


# ── gpt-image-1 prompts ────────────────────────────────────────────────────────
#
# Prompt builder: fills the item slots based on which garments are actually
# selected, keeping the wording clean when optional items are absent.

def _build_tryon_prompt(
    top: str | None = None,
    bottom: str | None = None,
    shoes: str | None = None,
    outerwear: str | None = None,
    category: str | None = None,        # used for single-garment path
    garment_name: str | None = None,    # used for single-garment path
) -> str:
    """
    Build the try-on prompt, populating only the slots for selected items.
    Handles both multi-garment (top/bottom/shoes/outerwear) and single-garment calls.
    """
    # ── Item slot lines ───────────────────────────────────────────────────────
    if garment_name and category:
        # Single-garment path: map category → slot
        _slot_map = {
            "top": "top", "outerwear": "jacket", "dress": "top",
            "bottom": "bottom", "shoes": "shoes", "accessory": "top",
            "other": "top",
        }
        slot = _slot_map.get(category, "top")
        if slot == "top":     top = garment_name
        elif slot == "bottom": bottom = garment_name
        elif slot == "shoes":  shoes = garment_name
        elif slot == "jacket": outerwear = garment_name

    def _slot(label: str, value: str | None) -> str:
        return f"- {label}: {value}" if value else f"- {label}: [not selected — do NOT invent]"

    item_block = "\n".join([
        _slot("Top", top),
        _slot("Bottom", bottom),
        _slot("Shoes", shoes),
        _slot("Jacket / Outerwear (optional)", outerwear),
    ])

    has_jacket_and_top = bool(outerwear and top)

    jacket_rule = (
        "JACKET + TOP RULE: The jacket must be rendered slightly open or partially "
        "open so the shirt/top collar, chest area, and lower hem remain clearly visible "
        "underneath. Never fully hide the top behind the jacket. Natural layering only."
        if has_jacket_and_top else
        "If only a jacket is selected with no inner top specified, preserve a neutral "
        "plain inner layer — do not invent a visible garment."
    )

    return f"""\
You are a high-precision virtual try-on system.

Goal:
Apply the EXACT selected clothing items onto the person in the first image, \
preserving realism, identity, and garment fidelity. The additional images are \
the garment reference photos.

Selected items:
{item_block}

STRICT RULES (MANDATORY):
1. IDENTITY PRESERVATION
   The person's face, body shape, pose, skin tone, hair, and identity MUST remain \
completely unchanged.
   Preserve the original background, camera angle, lighting direction, and scene exactly.
   Do NOT change facial expression, beautify, stylize, or alter the person in any way.

2. GARMENT FIDELITY — TOP PRIORITY
   Use ONLY the exact garments from the provided reference images.
   Do NOT generate new designs, styles, or variations.
   Preserve the exact color, pattern, fabric texture, silhouette, fit, seams, buttons, \
zippers, pockets, collar style, cuff style, sleeve length, hem length, and any \
graphic or logo on each garment.
   Do NOT blend, hallucinate, or modify any clothing item.

3. REALISTIC FITTING & PHYSICS
   Clothing must fit naturally to the body with realistic folds, fabric tension, \
drape, and alignment.
   Align garments with body joints: shoulders, elbows, wrists, waist, hips, knees, ankles.
   Add realistic fabric behavior: wrinkles where fabric bends, stretch where fabric pulls, \
gravity on hanging fabric.
   Ensure proper perspective and scale relative to the person's body.

4. REGION CONTROL
   Modify ONLY the clothing regions required for each selected garment.
   Preserve all non-clothing regions EXACTLY: background, hands, face, hair, skin.

5. LAYERING LOGIC
   Correct physical order: inner top → outerwear → bottom → shoes.
   All selected items must be visible in the final image.
   {jacket_rule}

6. LIGHTING CONSISTENCY
   Match garment lighting to the original photo (shadow direction, highlight placement, \
ambient vs. direct light).
   Fabric surfaces must reflect light consistently with the environment.

7. PHOTOREALISM REQUIREMENTS
   The result must look like a real photograph taken with a camera — not AI art.
   No distortions, floating fabric, texture smearing, blur artifacts, or inconsistent edges.
   No cartoon, painterly, or stylised effects.
   High-detail fabric texture preservation on every garment.

NEGATIVE CONSTRAINTS (any violation = failure):
- No new clothing items invented
- No extra accessories, jewelry, belts, hats, sunglasses, or bags
- No style changes or color alterations to any garment
- No unrealistic proportions or duplicated limbs
- No artistic effects
- Background must be identical to the original

PRIORITY ORDER (if conflict arises):
1. Identity preservation — face and body identical to input
2. Garment fidelity — exact match to reference images
3. Realistic fitting and physics
4. Lighting consistency

OUTPUT:
A photorealistic image of the SAME person wearing the EXACT selected outfit, \
indistinguishable from a real photograph.\
"""


# Legacy constant aliases (kept for any direct references elsewhere)
_GPT_PROMPT_MULTI   = _build_tryon_prompt()   # placeholder; real call passes kwargs
_GPT_PROMPT_SINGLE  = _build_tryon_prompt()   # placeholder; real call passes kwargs


# ── gpt-image-1 single-garment ────────────────────────────────────────────────

async def _try_on_gpt(
    body_bytes: bytes,
    garment_bytes: bytes,
    garment_name: str,
    category: str,
) -> bytes | None:
    """
    Single-garment gpt-image-1 try-on using the high-precision prompt.
    The prompt is built dynamically with the exact garment name and slot.
    """
    from openai import AsyncOpenAI
    api_key = settings.OPENAI_API_KEY
    if not api_key:
        return None

    try:
        client = AsyncOpenAI(api_key=api_key)
        loop   = asyncio.get_running_loop()

        body_png    = await loop.run_in_executor(None, lambda: _make_inpaint_png(body_bytes, category))
        garment_png = await loop.run_in_executor(None, lambda: _garment_to_png(garment_bytes))

        body_io = io.BytesIO(body_png); body_io.name = "body.png"
        garm_io = io.BytesIO(garment_png); garm_io.name = "garment.png"

        # Build prompt with exact item name / category for this single garment
        prompt = _build_tryon_prompt(category=category, garment_name=garment_name)

        logger.info(
            f"gpt-image-1 single [{category}] '{garment_name}': "
            f"body={len(body_png)}B garment={len(garment_png)}B"
        )

        response = await client.images.edit(
            model="gpt-image-1",
            image=[body_io, garm_io],
            prompt=prompt,
            n=1,
            size="1024x1024",
        )
        result = base64.b64decode(response.data[0].b64_json)
        logger.info(f"gpt-image-1 single ok: {len(result)}B")
        return result

    except Exception as exc:
        logger.error(f"gpt-image-1 single failed: {exc}", exc_info=True)
        return None


# ── gpt-image-1 multi-garment (all in one call) ───────────────────────────────

async def _try_on_gpt_multi(
    body_bytes: bytes,
    garment_data: list[tuple[str, str, bytes]],  # (category, name, bytes)
) -> bytes | None:
    """
    Pass body + ALL garments in a single gpt-image-1 call using the full
    multi-garment prompt. Better quality than sequential single-item chaining.
    """
    from openai import AsyncOpenAI
    api_key = settings.OPENAI_API_KEY
    if not api_key:
        return None

    try:
        client = AsyncOpenAI(api_key=api_key)
        loop   = asyncio.get_running_loop()

        # Make a full-body transparent mask (all clothing zones)
        body_png = await loop.run_in_executor(None, lambda: _make_inpaint_png(body_bytes, "other"))

        body_io = io.BytesIO(body_png); body_io.name = "body.png"
        images  = [body_io]

        for i, (cat, name, gbytes) in enumerate(garment_data):
            gpng = await loop.run_in_executor(None, lambda b=gbytes: _garment_to_png(b))
            garm_io = io.BytesIO(gpng); garm_io.name = f"garment_{i}_{cat}.png"
            images.append(garm_io)

        # Map category → prompt slot
        _cat_to_slot = {
            "top": "top", "dress": "top", "other": "top",
            "bottom": "bottom",
            "shoes": "shoes",
            "outerwear": "outerwear",
            "accessory": "top",
        }
        slot_values: dict[str, str] = {}
        for cat, name, _ in garment_data:
            slot = _cat_to_slot.get(cat, "top")
            slot_values[slot] = name  # last one wins per slot

        prompt = _build_tryon_prompt(
            top=slot_values.get("top"),
            bottom=slot_values.get("bottom"),
            shoes=slot_values.get("shoes"),
            outerwear=slot_values.get("outerwear"),
        )

        categories = ", ".join(f"{name} ({cat})" for cat, name, _ in garment_data)
        logger.info(f"gpt-image-1 multi [{categories}]: {len(images)} images")

        response = await client.images.edit(
            model="gpt-image-1",
            image=images,
            prompt=prompt,
            n=1,
            size="1024x1024",
        )
        result = base64.b64decode(response.data[0].b64_json)
        logger.info(f"gpt-image-1 multi ok: {len(result)}B")
        return result

    except Exception as exc:
        logger.error(f"gpt-image-1 multi failed: {exc}", exc_info=True)
        return None


# ── IDM-VTON via Replicate (PRIMARY photorealistic engine) ────────────────────

def _run_idm_sync(
    human_bytes: bytes,
    garment_bytes: bytes,
    token: str,
    garment_desc: str = "garment",
    category: str = "upper_body",
) -> bytes | None:
    import time
    import random
    import replicate as _replicate

    os.environ["REPLICATE_API_TOKEN"] = token
    client = _replicate.Client(api_token=token)
    last_err = None

    # Map to IDM-VTON's expected category values
    idm_cat = _IDM_CATEGORY.get(category, "upper_body")

    # Pre-process to IDM-VTON's native 768×1024 resolution
    human_bytes   = _prepare_body_for_idm(human_bytes)
    garment_bytes = _prepare_garment_for_idm(garment_bytes)

    for model_ref in _IDM_VERSIONS:
        _input = {
            "human_img":      io.BytesIO(human_bytes),
            "garm_img":       io.BytesIO(garment_bytes),
            "garment_des":    garment_desc,
            "category":       idm_cat,      # "upper_body" | "lower_body" | "dresses"
            "crop":           False,
            "seed":           random.randint(0, 2147483647),  # randomise for variety
            "steps":          40,            # ↑ from 30 — more denoising = sharper fit
            "force_dc":       False,
            "mask_only":      False,
            "is_checked":     True,          # enable DensePose-based body segmentation
            "is_checked_crop": False,
        }
        try:
            logger.info(f"IDM-VTON [{idm_cat}]: {model_ref[:55]}...")
            output = client.run(model_ref, input=_input)
            if output is None:
                continue
            if hasattr(output, "read"):
                data = output.read()
                logger.info(f"IDM-VTON ok: {len(data)}B")
                return data
            import urllib.request
            with urllib.request.urlopen(str(output), timeout=90) as r:
                data = r.read()
            logger.info(f"IDM-VTON ok (url): {len(data)}B")
            return data
        except Exception as exc:
            err = str(exc)
            last_err = exc
            if "429" in err or "throttled" in err.lower():
                logger.warning("IDM-VTON rate-limited, waiting 65s…")
                time.sleep(65)
                continue
            elif any(k in err for k in ("422", "404", "version", "not found")):
                continue
            raise

    logger.error(f"IDM-VTON all versions failed: {last_err}")
    return None


async def _try_on_idm(
    body_bytes: bytes,
    garment_bytes: bytes,
    garment_desc: str,
    category: str = "top",
) -> bytes | None:
    token = settings.REPLICATE_API_TOKEN
    if not token:
        return None
    try:
        # Pre-processing now happens inside _run_idm_sync (_prepare_body/garment_for_idm)
        # so we pass raw bytes here — no double-resize
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(
            None, partial(_run_idm_sync, body_bytes, garment_bytes, token, garment_desc, category)
        )
    except Exception as exc:
        logger.error(f"IDM-VTON failed: {exc}", exc_info=True)
        return None


# ── PIL composite (last-resort fallback) ──────────────────────────────────────

def _pil_overlay(body_bytes: bytes, garment_items: list[tuple[str, bytes]]) -> bytes:
    from rembg import remove as _rembg_remove

    body = Image.open(io.BytesIO(body_bytes)).convert("RGBA")
    bw, bh = body.size

    _anchor = {"top": 0.15, "outerwear": 0.10, "bottom": 0.44,
               "dress": 0.12, "shoes": 0.78, "accessory": 0.08, "other": 0.15}
    _h_frac = {"top": 0.42, "outerwear": 0.48, "bottom": 0.48,
               "dress": 0.78, "shoes": 0.18, "accessory": 0.20, "other": 0.40}

    for cat, gbytes in garment_items:
        try:
            try:
                gbytes = _rembg_remove(gbytes)
            except Exception:
                pass
            g = Image.open(io.BytesIO(gbytes)).convert("RGBA")
            bbox = g.getbbox()
            if bbox:
                g = g.crop(bbox)
            t_h = int(bh * _h_frac.get(cat, 0.40))
            t_w = int(t_h * g.width / max(1, g.height))
            g = g.resize((t_w, t_h), Image.Resampling.LANCZOS)
            x = (bw - t_w) // 2
            y = int(bh * _anchor.get(cat, 0.15))
            body.paste(g, (x, y), g)
        except Exception as exc:
            logger.warning(f"PIL overlay failed for {cat}: {exc}")

    buf = io.BytesIO()
    body.convert("RGB").save(buf, format="JPEG", quality=90)
    return buf.getvalue()


# ── Main entry point ───────────────────────────────────────────────────────────

async def generate_try_on_preview(
    user_id: str,
    item_ids: list[str],
    db: AsyncSession,
    shopping_item_ids: list[str] | None = None,
) -> bytes:
    import uuid as _uuid
    from app.models.user import User

    # Fetch user
    result = await db.execute(select(User).where(User.id == _uuid.UUID(str(user_id))))
    user = result.scalar_one_or_none()
    if not user:
        raise RuntimeError("User not found")

    if not user.body_photo_url:
        raise RuntimeError(
            "No body photo found. Please upload a full-body photo in your profile first."
        )

    # Fetch clothing items
    item_uuids = [_uuid.UUID(str(i)) for i in item_ids]
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.id.in_(item_uuids))
    )
    clothing_items = result.scalars().all()
    if not clothing_items:
        raise RuntimeError("No clothing items found")

    # Download body photo
    async with httpx.AsyncClient(timeout=30.0) as hc:
        resp = await hc.get(user.body_photo_url)
        resp.raise_for_status()
        body_bytes = resp.content
        logger.info(f"Body photo: {len(body_bytes)} bytes")

    # Sort: bottom → shoes → dress → top → outerwear
    sorted_items = sorted(
        clothing_items,
        key=lambda x: _LAYER_ORDER.get(
            (x.category.value if hasattr(x.category, "value") else str(x.category)).lower(), 5
        ),
    )

    # Download garment images
    garment_data: list[tuple[ClothingItem, bytes]] = []
    async with httpx.AsyncClient(timeout=30.0) as hc:
        for item in sorted_items:
            url = item.cleaned_image_url or item.original_image_url
            if not url:
                continue
            try:
                r = await hc.get(url)
                r.raise_for_status()
                garment_data.append((item, r.content))
                logger.info(f"Garment '{item.name}': {len(r.content)} bytes")
            except Exception as exc:
                logger.warning(f"Failed to download garment {item.id}: {exc}")

    if not garment_data:
        raise RuntimeError("Could not download any garment images")

    # ── PRIMARY: IDM-VTON with per-item gpt-image-1 fallback ─────────────────────
    # Separate items: AI-try-on items vs PIL-overlay items (shoes / accessories)
    ai_items:  list[tuple[ClothingItem, bytes]] = []
    pil_items: list[tuple[str, bytes]] = []

    for item, gbytes in garment_data:
        cat = (item.category.value if hasattr(item.category, "value")
               else str(item.category)).lower()
        if cat in _IDM_SUPPORTED:
            ai_items.append((item, gbytes))
        else:
            # shoes, accessories → PIL composite at the end (no AI try-on)
            logger.info(f"Queuing '{item.name}' [{cat}] for PIL overlay (not IDM-VTON supported)")
            pil_items.append((cat, gbytes))

    current_person = body_bytes
    successful = 0

    for idx, (item, garment_bytes) in enumerate(ai_items):
        cat = (item.category.value if hasattr(item.category, "value")
               else str(item.category)).lower()

        result_bytes = None

        # 1. Try IDM-VTON first (photorealistic, fast)
        if settings.REPLICATE_API_TOKEN:
            logger.info(f"IDM-VTON ({idx+1}/{len(ai_items)}): '{item.name}' [{cat}]")
            result_bytes = await _try_on_idm(
                body_bytes=current_person,
                garment_bytes=garment_bytes,
                garment_desc=item.name or cat,
                category=cat,
            )
            if result_bytes:
                logger.info(f"✓ IDM-VTON: '{item.name}'")
            else:
                logger.warning(f"✗ IDM-VTON failed for '{item.name}' — trying gpt-image-1")

        # 2. Per-item gpt-image-1 fallback if IDM-VTON failed
        if result_bytes is None and settings.OPENAI_API_KEY:
            logger.info(f"gpt-image-1 fallback for '{item.name}' [{cat}]")
            result_bytes = await _try_on_gpt(
                body_bytes=current_person,
                garment_bytes=garment_bytes,
                garment_name=item.name or cat,
                category=cat,
            )
            if result_bytes:
                logger.info(f"✓ gpt-image-1 fallback: '{item.name}'")
            else:
                logger.warning(f"✗ gpt-image-1 also failed for '{item.name}' — skipping")

        if result_bytes:
            loop = asyncio.get_running_loop()
            result_bytes = await loop.run_in_executor(
                None, lambda r=result_bytes: _restore_face(body_bytes, r)
            )
            current_person = result_bytes
            successful += 1

    if successful > 0:
        logger.info(f"Try-on complete: {successful}/{len(ai_items)} AI-applied")
        # Apply shoes / accessories via PIL composite on top of AI result
        if pil_items:
            logger.info(f"PIL overlay: {len(pil_items)} accessory/shoe items")
            loop = asyncio.get_running_loop()
            current_person = await loop.run_in_executor(
                None, lambda: _pil_overlay(current_person, pil_items)
            )
        return current_person

    logger.warning("All per-item try-on methods failed, trying gpt-image-1 multi…")

    # ── FALLBACK: gpt-image-1 ─────────────────────────────────────────────────
    if settings.OPENAI_API_KEY:
        gpt_items = [
            (
                (item.category.value if hasattr(item.category, "value")
                 else str(item.category)).lower(),
                item.name or "garment",
                gbytes,
            )
            for item, gbytes in ai_items
        ]

        if len(gpt_items) > 1:
            # Multi-garment: single call with all garments + full layering prompt
            logger.info(f"gpt-image-1 multi try-on: {len(gpt_items)} garments")
            result_bytes = await _try_on_gpt_multi(body_bytes, gpt_items)
        else:
            # Single garment: targeted inpainting
            cat, name, gbytes = gpt_items[0]
            result_bytes = await _try_on_gpt(body_bytes, gbytes, name, cat)

        if result_bytes:
            loop = asyncio.get_running_loop()
            result_bytes = await loop.run_in_executor(
                None, lambda r=result_bytes: _restore_face(body_bytes, r)
            )
            # Apply shoes / accessories via PIL on top of AI result
            if pil_items:
                result_bytes = await loop.run_in_executor(
                    None, lambda: _pil_overlay(result_bytes, pil_items)
                )
            logger.info("gpt-image-1 try-on complete")
            return result_bytes

    # ── LAST RESORT: PIL overlay (all items including AI-supported ones) ──────
    logger.warning("All AI try-on methods failed — using PIL overlay")
    all_pil = [
        (
            (item.category.value if hasattr(item.category, "value") else str(item.category)).lower(),
            gbytes,
        )
        for item, gbytes in garment_data  # garment_data = ai_items + pil originals
    ]
    return _pil_overlay(body_bytes, all_pil)

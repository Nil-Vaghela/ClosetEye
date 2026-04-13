"""
Flatlay Service
===============
Generates a clean outfit-board image from selected wardrobe items.

NO human body, NO model, NO mannequin — pure product/editorial flatlay.

Pipeline
--------
1. Download each garment image from storage.
2. Create a white 1024×1024 base canvas.
3. Call gpt-image-1 images.edit with:
   - white canvas  (base image — fully opaque so the model can compose freely)
   - all garment images as additional reference inputs
   - strict flatlay prompt with exact item names
4. Return the generated PNG bytes.

The caller persists and serves the image; this service only produces bytes.
"""
from __future__ import annotations

import asyncio
import base64
import io
import logging
from typing import List, Tuple

import httpx
from PIL import Image
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.clothing import ClothingItem
from app.core.config import settings

logger = logging.getLogger(__name__)

# ─── Prompt template ─────────────────────────────────────────────────────────

def _build_prompt(
    top: str | None,
    bottom: str | None,
    shoes: str | None,
    outerwear: str | None,
    accessories: list[str],
) -> str:
    """Build a focused flatlay prompt using only the items actually selected."""
    item_lines: list[str] = []
    if top:        item_lines.append(f"- Top: {top}")
    if outerwear:  item_lines.append(f"- Jacket / Outerwear: {outerwear}")
    if bottom:     item_lines.append(f"- Bottom: {bottom}")
    if shoes:      item_lines.append(f"- Shoes: {shoes}")
    for a in accessories:
        item_lines.append(f"- Accessory: {a}")

    selected_block = "\n".join(item_lines) if item_lines else "- (see reference images)"

    return f"""\
You are a fashion outfit composition engine for a digital wardrobe app.

Goal:
Generate a clean, realistic, high-quality outfit flatlay / product-style \
composition using ONLY the clothing items shown in the provided reference images. \
This is NOT a virtual try-on and must NOT show a human model, body, mannequin, \
hanger person, or avatar. The output must be an outfit preview only.

Selected items:
{selected_block}

Instructions:
1. Use only the exact garments from the uploaded reference images as the outfit components.
2. Do not invent, replace, restyle, or substitute any clothing item.
3. Do not add extra garments, accessories, jewelry, bags, hats, watches, sunglasses, \
belts, or props unless explicitly provided.
4. Show the outfit as a complete styled combination arranged neatly in a clean \
fashion-editorial layout.
5. Preserve the true color, fabric, silhouette, texture, fit, and design details \
of each item.
6. Maintain item accuracy — if the selected top is black it must remain black; \
if the shoes are white sneakers they must remain white sneakers.
7. The composition must look premium, realistic, and ecommerce-quality.
8. Background should be minimal, clean, and neutral — white, off-white, or \
light gray studio backdrop.
9. Arrange the outfit in a visually balanced way:
   - top placed above bottom
   - jacket layered beside or partially over the top if included
   - shoes placed below the bottom
10. If a jacket is included, style it as part of the composition without hiding \
the top completely.
11. Prefer a laid-out outfit styling presentation; do not fold garments.
12. No text, labels, watermarks, UI elements, pricing tags, or branding overlays.
13. Output should look like a polished outfit board for styling and wardrobe planning.
14. Emphasise realism, garment fidelity, and tasteful spacing.
15. Do not create a person wearing the outfit. Outfit preview only.

Output style: realistic fashion flatlay, premium wardrobe-planner aesthetic, \
clean studio lighting, highly detailed garment textures, balanced composition, \
modern styling board.

HARD CONSTRAINTS (violations = failure):
- No human body, face, mannequin, model, avatar, or virtual try-on
- No extra clothing items, replacement garments, colour changes, or style changes
- No invented accessories, background clutter, text, watermark, or logo
- No duplicate items, distorted garments

Priority: (1) exact item fidelity → (2) realistic outfit arrangement → \
(3) premium visual presentation
"""


# ─── White canvas helper ──────────────────────────────────────────────────────

def _white_canvas(size: int = 1024) -> bytes:
    """Create a solid-white RGBA PNG as the base image for gpt-image-1 inpainting."""
    img = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _garment_png(garment_bytes: bytes, max_dim: int = 768) -> bytes:
    """Resize garment image and convert to PNG."""
    img = Image.open(io.BytesIO(garment_bytes)).convert("RGBA")
    w, h = img.size
    if max(w, h) > max_dim:
        scale = max_dim / max(w, h)
        img = img.resize((int(w * scale), int(h * scale)), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


# ─── Main entry point ─────────────────────────────────────────────────────────

async def generate_flatlay(
    item_ids: list[str],
    db: AsyncSession,
) -> bytes:
    """
    Generate a flatlay outfit image for the given wardrobe item IDs.

    Returns raw PNG/JPEG bytes of the composed outfit board.
    Raises RuntimeError on any unrecoverable failure.
    """
    import uuid as _uuid

    if not settings.OPENAI_API_KEY:
        raise RuntimeError(
            "Flatlay generation requires an OpenAI API key (gpt-image-1). "
            "Please add OPENAI_API_KEY to your .env."
        )

    # ── Fetch clothing items ──────────────────────────────────────────────────
    item_uuids = [_uuid.UUID(str(i)) for i in item_ids]
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.id.in_(item_uuids))
    )
    items: list[ClothingItem] = list(result.scalars().all())
    if not items:
        raise RuntimeError("No clothing items found for the provided IDs.")

    # ── Download garment images ───────────────────────────────────────────────
    garment_data: list[tuple[ClothingItem, bytes]] = []
    async with httpx.AsyncClient(timeout=30.0) as hc:
        for item in items:
            url = item.cleaned_image_url or item.original_image_url
            if not url:
                logger.warning(f"Item '{item.name}' has no image URL — skipping")
                continue
            try:
                r = await hc.get(url)
                r.raise_for_status()
                garment_data.append((item, r.content))
                logger.info(f"Flatlay garment '{item.name}': {len(r.content)} B")
            except Exception as exc:
                logger.warning(f"Failed to download garment {item.id}: {exc}")

    if not garment_data:
        raise RuntimeError("Could not download any garment images.")

    # ── Classify items by slot ────────────────────────────────────────────────
    _top = _bottom = _shoes = _outerwear = None
    _accessories: list[str] = []

    for item, _ in garment_data:
        cat = (item.category.value if hasattr(item.category, "value")
               else str(item.category)).lower()
        name = item.name or cat
        if cat in ("top",):                _top = name
        elif cat in ("bottom",):           _bottom = name
        elif cat in ("shoes",):            _shoes = name
        elif cat in ("outerwear",):        _outerwear = name
        elif cat in ("dress",):            _top = name      # treat dress like a top
        elif cat in ("accessory", "other"):_accessories.append(name)

    prompt = _build_prompt(_top, _bottom, _shoes, _outerwear, _accessories)

    # ── Call gpt-image-1 ──────────────────────────────────────────────────────
    loop = asyncio.get_running_loop()

    # Pre-process garment images in executor (CPU work)
    canvas_bytes = await loop.run_in_executor(None, _white_canvas)

    processed_garments: list[bytes] = []
    for item, gbytes in garment_data:
        pg = await loop.run_in_executor(None, lambda b=gbytes: _garment_png(b))
        processed_garments.append(pg)

    logger.info(
        f"Flatlay: {len(processed_garments)} garments, prompt length={len(prompt)}"
    )

    try:
        from openai import AsyncOpenAI
        client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

        canvas_io = io.BytesIO(canvas_bytes)
        canvas_io.name = "canvas.png"
        images = [canvas_io]

        for i, gpng in enumerate(processed_garments):
            cat = (garment_data[i][0].category.value
                   if hasattr(garment_data[i][0].category, "value")
                   else str(garment_data[i][0].category)).lower()
            garm_io = io.BytesIO(gpng)
            garm_io.name = f"garment_{i}_{cat}.png"
            images.append(garm_io)

        response = await client.images.edit(
            model="gpt-image-1",
            image=images,
            prompt=prompt,
            n=1,
            size="1024x1024",
        )
        result_bytes = base64.b64decode(response.data[0].b64_json)
        logger.info(f"Flatlay generated: {len(result_bytes)} B")
        return result_bytes

    except Exception as exc:
        logger.error(f"gpt-image-1 flatlay failed: {exc}", exc_info=True)
        raise RuntimeError(f"Flatlay generation failed: {exc}") from exc

"""
Personal try-on avatar ("digital twin").

From one full-body photo + height/weight/body type, generate a clean studio photo
of the SAME person in neutral fitted base layers, standing front-facing. All
virtual try-ons then run on this avatar, which gives cleaner, consistent results
than messy real-world photos (coats, bags, odd poses, busy backgrounds).
"""
from __future__ import annotations

import io
import logging

from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

_PROMPT = (
    "Create a photorealistic full-body studio photo of THIS EXACT SAME PERSON from the reference photo. "
    "Keep their face, identity, skin tone, hair and body proportions exactly. "
    "Body: height {height} cm, weight {weight} kg, {body_type} build. "
    "They stand straight facing the camera, arms relaxed slightly away from the body, feet slightly apart, "
    "neutral friendly expression. They wear simple fitted neutral base layers: a plain light grey crew-neck "
    "fitted t-shirt and plain fitted light grey pants, barefoot. Plain soft warm off-white seamless studio "
    "background, soft even lighting, head to toe fully visible and centered, nothing else in the frame."
)


async def generate_avatar(photo: bytes, height_cm: int, weight_kg: int, body_type: str) -> bytes | None:
    """Returns PNG bytes, or None if the avatar can't be made (caller falls back to the photo)."""
    if not settings.VERTEX_PROJECT:
        return None
    from google import genai
    from google.genai import types

    from app.services.ai_client import _with_retry

    client = genai.Client(vertexai=True, project=settings.VERTEX_PROJECT, location=settings.VERTEX_LOCATION)
    prompt = _PROMPT.format(height=height_cm, weight=weight_kg, body_type=body_type)
    contents = [types.Part.from_bytes(data=photo, mime_type="image/jpeg"), prompt]
    cfg = types.GenerateContentConfig(
        response_modalities=["IMAGE"], image_config=types.ImageConfig(aspect_ratio="3:4")
    )
    for model in (settings.VERTEX_AVATAR_MODEL, settings.VERTEX_IMAGE_MODEL):
        try:
            resp = await _with_retry(
                lambda m=model: client.aio.models.generate_content(model=m, contents=contents, config=cfg), attempts=3
            )
            for cand in resp.candidates or []:
                for part in (cand.content.parts if cand.content else []) or []:
                    if part.inline_data and part.inline_data.data:
                        out = io.BytesIO()
                        Image.open(io.BytesIO(part.inline_data.data)).convert("RGB").save(out, format="PNG")
                        return out.getvalue()
        except Exception:
            logger.exception("Avatar generation failed with %s", model)
    return None

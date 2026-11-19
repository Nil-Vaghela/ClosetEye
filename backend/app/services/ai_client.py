"""
One AI client for the whole app, switchable by AI_PROVIDER:

- "vertex" (default when VERTEX_PROJECT is set): Google Gemini on Vertex AI, billed to
  Google Cloud (our $300 credit). Auth is the Cloud Run service account; no API key.
- "openai": the original OpenAI path.

The Gemini adapter exposes the small slice of the OpenAI SDK the code already uses
(`chat.completions.create` and `images.edit/generate`), so the services didn't need rewriting:
  response.choices[0].message.content   -> text
  response.data[0].b64_json             -> generated image (PNG, base64)
"""
from __future__ import annotations

import asyncio
import base64
import io
import logging
import random
from types import SimpleNamespace
from typing import Any

from app.core.config import settings

logger = logging.getLogger(__name__)

_client: Any = None


def provider() -> str:
    p = (settings.AI_PROVIDER or "").lower()
    if p in ("vertex", "openai"):
        return p
    return "vertex" if settings.VERTEX_PROJECT else "openai"


def ai_enabled() -> bool:
    if provider() == "vertex":
        return bool(settings.VERTEX_PROJECT)
    return bool(settings.OPENAI_API_KEY)


def get_ai_client():
    """OpenAI-compatible async client, or None when AI isn't configured."""
    global _client
    if _client is not None:
        return _client
    if not ai_enabled():
        return None
    if provider() == "vertex":
        _client = GeminiCompat()
    else:
        from openai import AsyncOpenAI
        _client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
    return _client


# ── Gemini adapter ───────────────────────────────────────────────────────────

def _data_url_bytes(url: str) -> tuple[bytes, str] | None:
    if not url.startswith("data:"):
        return None
    head, b64 = url.split(",", 1)
    mime = head[5:].split(";", 1)[0] or "image/jpeg"
    return base64.b64decode(b64), mime


def _file_bytes(f) -> bytes:
    if isinstance(f, (bytes, bytearray)):
        return bytes(f)
    if hasattr(f, "getvalue"):
        return f.getvalue()
    pos = f.tell() if hasattr(f, "tell") else None
    data = f.read()
    if pos is not None:
        f.seek(pos)
    return data


def _sniff(data: bytes) -> str:
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


# New Vertex projects get small per-minute quotas; smooth bursts instead of failing.
_IMAGE_SLOTS = asyncio.Semaphore(2)


async def _with_retry(call, attempts: int = 5):
    delay = 2.0
    for i in range(attempts):
        try:
            return await call()
        except Exception as exc:  # google.genai.errors.ClientError carries .code
            code = getattr(exc, "code", None)
            retryable = code in (429, 503) or "RESOURCE_EXHAUSTED" in str(exc)
            if not retryable or i == attempts - 1:
                raise
            await asyncio.sleep(delay + random.random())
            delay *= 2


class _Chat:
    def __init__(self, outer: "GeminiCompat"):
        self.completions = SimpleNamespace(create=outer._chat_create)


class _Images:
    def __init__(self, outer: "GeminiCompat"):
        self.edit = outer._image_edit
        self.generate = outer._image_generate


class GeminiCompat:
    def __init__(self):
        from google import genai

        self._genai = genai.Client(
            vertexai=True, project=settings.VERTEX_PROJECT, location=settings.VERTEX_LOCATION
        )
        self.chat = _Chat(self)
        self.images = _Images(self)

    # chat.completions.create(model=..., messages=[...], max_tokens=..., temperature=...)
    async def _chat_create(self, *, messages: list[dict], max_tokens: int | None = None,
                           temperature: float | None = None, response_format: Any = None, **_: Any):
        from google.genai import types

        system_parts: list[str] = []
        contents: list[types.Content] = []
        for m in messages:
            role, content = m.get("role", "user"), m.get("content")
            if role == "system":
                system_parts.append(content if isinstance(content, str) else str(content))
                continue
            parts: list[types.Part] = []
            if isinstance(content, str):
                parts.append(types.Part.from_text(text=content))
            else:
                for c in content or []:
                    if c.get("type") == "text":
                        parts.append(types.Part.from_text(text=c["text"]))
                    elif c.get("type") == "image_url":
                        url = c["image_url"]["url"] if isinstance(c["image_url"], dict) else c["image_url"]
                        decoded = _data_url_bytes(url)
                        if decoded:
                            parts.append(types.Part.from_bytes(data=decoded[0], mime_type=decoded[1]))
            contents.append(types.Content(role="model" if role == "assistant" else "user", parts=parts))

        wants_json = bool(response_format) and "json" in str(response_format)
        cfg = types.GenerateContentConfig(
            system_instruction="\n\n".join(system_parts) or None,
            # OpenAI-style small max_tokens would be eaten by thinking; give headroom.
            max_output_tokens=max(2048, (max_tokens or 0) * 2),
            temperature=temperature,
            thinking_config=types.ThinkingConfig(thinking_level="low"),
            response_mime_type="application/json" if wants_json else None,
        )
        resp = await _with_retry(lambda: self._genai.aio.models.generate_content(
            model=settings.VERTEX_TEXT_MODEL, contents=contents, config=cfg
        ))
        text = resp.text or ""
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=text))])

    async def _generate_image(self, prompt: str, images: list[bytes]):
        from google.genai import types

        parts = [types.Part.from_bytes(data=b, mime_type=_sniff(b)) for b in images]
        parts.append(types.Part.from_text(text=prompt))
        cfg = types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(aspect_ratio="1:1"),
        )
        async def _call(model: str, attempts: int):
            return await _with_retry(lambda: self._genai.aio.models.generate_content(
                model=model, contents=[types.Content(role="user", parts=parts)], config=cfg,
            ), attempts=attempts)

        async with _IMAGE_SLOTS:
            try:
                resp = await _call(settings.VERTEX_IMAGE_MODEL, 3)
            except Exception as exc:
                busy = getattr(exc, "code", None) in (429, 503) or "RESOURCE_EXHAUSTED" in str(exc)
                if not (busy and settings.VERTEX_IMAGE_FALLBACK_MODEL):
                    raise
                logger.warning("Image model busy; using fallback %s", settings.VERTEX_IMAGE_FALLBACK_MODEL)
                resp = await _call(settings.VERTEX_IMAGE_FALLBACK_MODEL, 3)
        for cand in resp.candidates or []:
            for p in (cand.content.parts if cand.content else []) or []:
                if p.inline_data and p.inline_data.data:
                    png = _to_png(p.inline_data.data)
                    return SimpleNamespace(data=[SimpleNamespace(b64_json=base64.b64encode(png).decode(), url=None)])
        raise RuntimeError("The image model didn't return an image")

    # images.edit(model=..., image=<file or list>, prompt=..., ...)
    async def _image_edit(self, *, image, prompt: str, mask=None, **_: Any):
        files = image if isinstance(image, list) else [image]
        return await self._generate_image(prompt, [_file_bytes(f) for f in files])

    # images.generate(model=..., prompt=..., ...)
    async def _image_generate(self, *, prompt: str, **_: Any):
        return await self._generate_image(prompt, [])


def _to_png(data: bytes) -> bytes:
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return data
    from PIL import Image

    out = io.BytesIO()
    Image.open(io.BytesIO(data)).save(out, format="PNG")
    return out.getvalue()

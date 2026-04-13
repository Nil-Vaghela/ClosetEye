"""
AI service layer — wraps OpenAI API calls for:
- Clothing attribute detection (color, category, season, pattern)
- Outfit compatibility scoring (mix-match)
- Wardrobe analysis (style DNA, capsule score, gap analysis)
- Shopping recommendations
- DALL-E 3 product image generation (clean flat-lay)
- DALL-E 3 virtual try-on generation (realistic full-body)
"""
from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


def _default_attributes() -> dict:
    """Fallback attributes when API unavailable or fails."""
    return {
        "name": None,
        "category": "other",
        "color_primary": "#999999",
        "color_secondary": None,
        "season": "all",
        "tags": [],
        "pattern": None,
    }


def _strip_fences(text: str) -> str:
    """Strip markdown code fences from LLM JSON output."""
    text = text.strip()
    if text.startswith("```"):
        parts = text.split("```")
        text = parts[1] if len(parts) > 1 else text
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    if text.endswith("```"):
        text = text[:-3].strip()
    return text


def _mime_from_bytes(data: bytes) -> str:
    """Detect image MIME type from magic bytes."""
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"  # safe default for OpenAI


def _b64_data_url(image_bytes: bytes) -> str:
    """Return a base64 data URL with the correct MIME type."""
    mime = _mime_from_bytes(image_bytes)
    b64 = base64.standard_b64encode(image_bytes).decode("utf-8")
    return f"data:{mime};base64,{b64}"


class AIService:
    """Singleton-style service for all AI operations."""

    def __init__(self):
        self._client = None

    def _get_client(self):
        """Lazily initialize OpenAI async client."""
        if self._client is None:
            if not settings.OPENAI_API_KEY:
                logger.warning("OPENAI_API_KEY not set; AI features will use fallbacks")
                return None
            from openai import AsyncOpenAI
            self._client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        return self._client

    async def detect_photo_type(self, image_bytes: bytes) -> str:
        """
        Use OpenAI Vision to detect if photo shows a worn item or a flat lay.
        Returns "worn" or "flatlay".
        """
        client = self._get_client()
        if not client:
            logger.warning("No OpenAI client; falling back to heuristic detection")
            from app.services.garment_service import detect_photo_type_heuristic
            return detect_photo_type_heuristic(image_bytes).value

        try:
            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=50,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": _b64_data_url(image_bytes),
                                    "detail": "low",
                                },
                            },
                            {
                                "type": "text",
                                "text": (
                                    "Is this a photo of a clothing item worn on a person's body, "
                                    "or a flat lay photo of clothing on a surface? "
                                    "Respond with only 'worn' or 'flatlay'."
                                ),
                            },
                        ],
                    }
                ],
            )

            result = response.choices[0].message.content.strip().lower()
            if "worn" in result:
                return "worn"
            return "flatlay"

        except Exception as exc:
            logger.error(f"Photo type detection failed: {exc}")
            return "flatlay"

    async def detect_attributes(self, image_bytes: bytes) -> dict:
        """
        Detect color, category, pattern, etc. from a cleaned garment image.
        Returns a dict with keys: name, category, color_primary, color_secondary,
        season, tags, pattern.
        """
        client = self._get_client()
        if not client:
            logger.warning("No OpenAI client; using fallback attributes")
            return _default_attributes()

        try:
            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=500,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": _b64_data_url(image_bytes),
                                    "detail": "low",
                                },
                            },
                            {
                                "type": "text",
                                "text": (
                                    "Analyze this clothing item image and return a JSON object with these fields:\n"
                                    '{\n'
                                    '  "name": "brief item name or null",\n'
                                    '  "category": "top|bottom|outerwear|dress|shoes|accessory|other",\n'
                                    '  "color_primary": "hex code or color name",\n'
                                    '  "color_secondary": "hex code or color name or null",\n'
                                    '  "season": "spring|summer|fall|winter|all",\n'
                                    '  "tags": ["tag1", "tag2"] (max 4 relevant tags like \'casual\', \'work\', \'formal\'),\n'
                                    '  "pattern": "solid|striped|floral|plaid|polka|animal|geometric|other or null"\n'
                                    "}\n\n"
                                    "Return ONLY the JSON object, no markdown or explanation."
                                ),
                            },
                        ],
                    }
                ],
            )

            text = _strip_fences(response.choices[0].message.content)
            attrs = json.loads(text)

            if not isinstance(attrs.get("tags"), list):
                attrs["tags"] = []
            attrs["tags"] = attrs["tags"][:4]

            logger.info(f"Detected attributes: {attrs}")
            return attrs

        except json.JSONDecodeError as exc:
            logger.error(f"Failed to parse attributes JSON: {exc}")
            return _default_attributes()
        except Exception as exc:
            logger.error(f"Attribute detection failed: {exc}")
            return _default_attributes()

    async def score_outfit(self, item_image_urls: list[str]) -> float:
        """
        Score how well a set of clothing items go together (0.0 – 1.0).
        Defaults to 0.75 on error or missing API key.
        """
        client = self._get_client()
        if not client:
            return 0.75

        try:
            content: list[dict] = [
                {
                    "type": "text",
                    "text": (
                        "You are a fashion expert. Rate how well these clothing items "
                        "coordinate together on a scale of 0-10, considering color harmony, "
                        "style cohesion, and appropriateness. Respond with ONLY a number 0-10."
                    ),
                }
            ]

            for url in item_image_urls[:5]:
                content.append({
                    "type": "image_url",
                    "image_url": {"url": url, "detail": "low"},
                })

            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=10,
                messages=[{"role": "user", "content": content}],
            )

            score_text = response.choices[0].message.content.strip()
            score = float(score_text) / 10.0
            return max(0.0, min(1.0, score))

        except Exception as exc:
            logger.error(f"Outfit scoring failed: {exc}")
            return 0.75

    async def suggest_outfits(
        self,
        wardrobe_items: list[dict],
        occasion: str | None = None,
        season: str | None = None,
    ) -> list[dict]:
        """
        Suggest outfit combinations with rich styling metadata.

        Returns list of dicts:
        {
          "name": "Smart Casual Monday",
          "item_ids": ["uuid", ...],
          "description": "...",
          "occasion": "casual",
          "style_notes": "Why these pieces work together",
          "compatibility_score": 87,           // 0-100
          "warnings": ["Pattern clash: ..."],  // mismatch reasons
          "missing_piece": "A white belt would complete this look"
        }
        """
        client = self._get_client()
        if not client:
            return []

        try:
            wardrobe_desc = json.dumps(wardrobe_items, default=str)
            system = (
                "You are a personal fashion stylist with expertise in color theory, "
                "pattern mixing, and contemporary menswear/womenswear. "
                "Analyse the user's wardrobe and suggest complete outfit combinations. "
                "Be honest about mismatches — if items clash (colors, patterns, formality), "
                "call it out clearly in 'warnings'. Score outfits honestly."
            )
            prompt = (
                f"Wardrobe inventory:\n{wardrobe_desc}\n\n"
                f"Filters: occasion={occasion or 'any'}, season={season or 'any'}\n\n"
                "Suggest 5 outfit combinations. For each return a JSON object:\n"
                "{\n"
                '  "name": "short catchy outfit name (3-5 words)",\n'
                '  "item_ids": ["<id from wardrobe>", ...],\n'
                '  "description": "1-sentence outfit description",\n'
                '  "occasion": "casual|work|date night|formal|sport",\n'
                '  "style_notes": "1-2 sentences on WHY these pieces work together (colors, proportions, vibe)",\n'
                '  "compatibility_score": <integer 0-100>,\n'
                '  "warnings": ["<specific mismatch e.g. \'Striped top + checked trousers clash\'>" or empty array],\n'
                '  "missing_piece": "<optional: one item that would complete this look, or null>"\n'
                "}\n\n"
                "Return ONLY a JSON array of 5 objects, no markdown, no commentary."
            )

            response = await client.chat.completions.create(
                model="gpt-4o",
                max_tokens=2000,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user",   "content": prompt},
                ],
            )

            text = _strip_fences(response.choices[0].message.content)
            suggestions = json.loads(text)
            if not isinstance(suggestions, list):
                suggestions = suggestions.get("outfits", [])
            logger.info(f"Generated {len(suggestions)} rich outfit suggestions")
            return suggestions[:5]

        except Exception as exc:
            logger.error(f"Outfit suggestion failed: {exc}")
            return []

    async def analyze_style_dna(self, wardrobe_items: list[dict]) -> dict:
        """
        Analyze user's clothing style and return dominant style traits.
        Returns {dominant_style, style_scores, summary}.
        """
        client = self._get_client()
        if not client:
            return {
                "dominant_style": "unknown",
                "style_scores": {},
                "summary": "Style analysis unavailable — no API key configured.",
            }

        try:
            wardrobe_desc = json.dumps(wardrobe_items, default=str)
            prompt = (
                "Analyze this wardrobe for style traits. Return JSON:\n"
                '{\n'
                '  "dominant_style": "string (primary style e.g. minimalist/classic/streetwear)",\n'
                '  "style_scores": {"minimalist": 0.0-1.0, "classic": 0.0-1.0, ...},\n'
                '  "summary": "natural language summary 1-2 sentences"\n'
                '}\n\n'
                f"Wardrobe: {wardrobe_desc}\n\n"
                "Return ONLY JSON, no markdown."
            )

            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=500,
                messages=[{"role": "user", "content": prompt}],
            )

            text = _strip_fences(response.choices[0].message.content)
            result = json.loads(text)
            logger.info(f"Style DNA: {result.get('dominant_style')}")
            return result

        except Exception as exc:
            logger.error(f"Style DNA analysis failed: {exc}")
            return {
                "dominant_style": "unknown",
                "style_scores": {},
                "summary": "Analysis unavailable.",
            }

    async def calculate_capsule_score(self, wardrobe_items: list[dict]) -> int:
        """
        Estimate number of unique outfit combinations in wardrobe (heuristic, no API call).
        Returns 0-999.
        """
        try:
            category_count: dict[str, int] = {}
            for item in wardrobe_items:
                cat = item.get("category", "other")
                category_count[cat] = category_count.get(cat, 0) + 1

            tops = category_count.get("top", 0) + category_count.get("dress", 0)
            bottoms = category_count.get("bottom", 0)
            outerwear = max(1, category_count.get("outerwear", 0))
            shoes = max(1, category_count.get("shoes", 0))

            base = max(1, tops) * max(1, bottoms)
            score = int(base * outerwear * (shoes / 2))
            return min(999, score)

        except Exception as exc:
            logger.error(f"Capsule score calculation failed: {exc}")
            return 0

    async def detect_all_items(self, image_bytes: bytes) -> list[dict]:
        """
        STEP 1 + 5 of the wardrobe extraction pipeline.

        Uses GPT-4o (high detail) to:
        - Detect every wearable item on the person
        - Extract full attribute metadata per item
        - Return confidence score so low-confidence items are skipped

        Only includes items with confidence > 0.6.
        Returns list of rich item dicts matching the wardrobe spec.
        """
        client = self._get_client()
        if not client:
            return []

        _SYSTEM = (
            "You are a premium fashion AI for a digital wardrobe app. "
            "Analyse the image with expert precision. "
            "Think like a fashion photographer and clothing cataloguer. "
            "Be exact about colours (use hex codes), materials, and fit. "
            "Never hallucinate items that are not clearly visible."
        )

        _USER = (
            "Analyse this photo and identify every wearable item on the person.\n\n"
            "INCLUDE: shirts, t-shirts, jackets, hoodies, coats, trousers, "
            "jeans, shorts, skirts, dresses, shoes, sneakers, boots, "
            "caps, beanies, watches, bags, belts, scarves.\n\n"
            "EXCLUDE: background objects, furniture, and items not worn.\n\n"
            "For EACH item return a JSON object with EXACTLY these fields:\n"
            "{\n"
            '  "name": "human-readable name e.g. \'Navy Linen Button-Up Shirt\'",\n'
            '  "category": "top|bottom|outerwear|dress|shoes|accessory|other",\n'
            '  "subcategory": "e.g. linen shirt | formal trousers | leather sneakers",\n'
            '  "color_primary": "#hexcode",\n'
            '  "color_secondary": "#hexcode or null",\n'
            '  "color": ["#hexcode", ...],\n'
            '  "pattern": "solid|striped|floral|plaid|polka|printed|other",\n'
            '  "material": "best estimate e.g. cotton|linen|denim|leather|wool",\n'
            '  "fit": "slim|regular|oversized|relaxed",\n'
            '  "season": "spring|summer|fall|winter|all",\n'
            '  "tags": ["casual","formal","streetwear", ...],\n'
            '  "attributes": {\n'
            '    "sleeve": "short|long|sleeveless|rolled",\n'
            '    "collar": "open|button-down|crew|v-neck|turtleneck|none",\n'
            '    "length": "crop|hip|thigh|knee|ankle|full",\n'
            '    "closure": "buttons|zip|pullover|none",\n'
            '    "style": "casual|formal|athletic|streetwear"\n'
            "  },\n"
            '  "confidence": 0.0\n'
            "}\n\n"
            "Return a JSON ARRAY of these objects. "
            "Only include items with confidence > 0.6. "
            "Do not duplicate items. "
            "Return ONLY the JSON array, no markdown, no explanation."
        )

        try:
            response = await client.chat.completions.create(
                model="gpt-4o",
                max_tokens=2000,
                messages=[
                    {"role": "system", "content": _SYSTEM},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": _b64_data_url(image_bytes),
                                    "detail": "high",
                                },
                            },
                            {"type": "text", "text": _USER},
                        ],
                    },
                ],
            )

            text = _strip_fences(response.choices[0].message.content)
            items = json.loads(text)
            if not isinstance(items, list):
                items = [items]

            # Filter by confidence and normalise category names
            _CAT_MAP = {
                "upper_wear": "top", "lower_wear": "bottom",
                "footwear": "shoes", "accessory": "accessory",
                "outerwear": "outerwear", "dress": "dress",
            }
            result = []
            for item in items:
                if item.get("confidence", 1.0) < 0.6:
                    continue
                cat = item.get("category", "other")
                item["category"] = _CAT_MAP.get(cat, cat)
                # Back-fill legacy fields used downstream
                if not item.get("color_primary") and item.get("color"):
                    item["color_primary"] = item["color"][0] if item["color"] else None
                if not item.get("tags"):
                    item["tags"] = []
                result.append(item)

            logger.info(
                f"Detected {len(result)} items "
                f"(filtered from {len(items)} raw)"
            )
            return result

        except json.JSONDecodeError as exc:
            logger.error(f"Failed to parse items JSON: {exc}")
            return []
        except Exception as exc:
            logger.error(f"Multi-item detection failed: {exc}")
            return []

    async def describe_garment_from_photo(
        self,
        full_photo_bytes: bytes,
        item_name: str,
        item_category: str,
    ) -> str:
        """
        Step 1: GPT-4V looks at the full outfit photo and writes a hyper-detailed
        50-word description of ONE specific garment.

        E.g. for a shirt: "Soft lavender-purple linen casual button-up shirt,
        open collar with no tie, long sleeves slightly rolled to mid-forearm,
        5 visible buttons, relaxed oversized fit, crinkled linen texture,
        front chest pocket, untucked hem."

        This level of detail is what makes DALL-E 3 produce an accurate match.
        """
        client = self._get_client()
        if not client:
            return f"{item_name}"

        try:
            resp = await client.chat.completions.create(
                model="gpt-4o",
                max_tokens=120,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": _b64_data_url(full_photo_bytes),
                                "detail": "high",
                            },
                        },
                        {
                            "type": "text",
                            "text": (
                                f"Look at the {item_name} ({item_category}) the person is wearing. "
                                "Write a 50-word product description a fashion photographer would "
                                "use to recreate this exact item. Include: exact color name, "
                                "fabric/material, garment type, collar/neckline style, sleeve length, "
                                "fit (slim/relaxed/oversized), button/zipper details, any patterns, "
                                "texture, and unique design details. "
                                "Be extremely specific. No generic words. "
                                "Output ONLY the description, no labels or formatting."
                            ),
                        },
                    ],
                }],
            )
            desc = resp.choices[0].message.content.strip()
            logger.info(f"GPT-4V precision description for '{item_name}': {desc}")
            return desc
        except Exception as exc:
            logger.warning(f"GPT-4V description failed: {exc}")
            return item_name

    async def generate_product_image(
        self,
        attributes: dict,
        full_photo_bytes: bytes | None = None,
    ) -> bytes | None:
        """
        3-step pipeline to get a clean studio product image:

        STEP 1 — Garment crop
          rembg isolates the person from background, zone-crop selects the
          garment region (shirt / trousers / shoes).  Fast, no API needed.

        STEP 2 — gpt-image-1 clean render  (requires OpenAI key)
          The garment crop is sent to OpenAI's image-edit endpoint with a
          prompt telling it to render a clean e-commerce studio product shot:
          white background, no human body, preserve exact colour + design.

        STEP 3 — Fallback
          If gpt-image-1 fails for any reason, return the raw garment crop
          (still shows the real garment; just with some background/skin).
          Never returns None — worst case is the zone crop.
        """
        if full_photo_bytes is None:
            return None

        category  = attributes.get("category", "other")
        name      = attributes.get("name", "item")
        color_hex = attributes.get("color_primary") or ""

        # ── STEP 1: get garment crop via rembg zone crop ─────────────────────
        garment_crop: bytes | None = None
        try:
            from app.services.garment_service import extract_product_image_for_category
            loop = asyncio.get_running_loop()
            garment_crop = await loop.run_in_executor(
                None,
                lambda: extract_product_image_for_category(full_photo_bytes, category),
            )
            logger.info(f"Garment crop for '{name}': {len(garment_crop)} bytes")
        except Exception as exc:
            logger.warning(f"Garment crop failed for '{name}': {exc}")

        if not garment_crop:
            logger.error(f"Could not extract any crop for '{name}'; skipping product image")
            return None

        # ── STEP 2: gpt-image-1 clean product render ─────────────────────────
        client = self._get_client()
        if client:
            try:
                result = await self._render_via_gpt_image(
                    client, garment_crop, name, category, color_hex
                )
                if result:
                    logger.info(
                        f"gpt-image-1 product image for '{name}': {len(result)} bytes"
                    )
                    return result
                logger.warning(f"gpt-image-1 returned no result for '{name}'")
            except Exception as exc:
                logger.warning(
                    f"gpt-image-1 failed for '{name}': {exc}; returning raw crop"
                )

        # ── STEP 3: fallback — return raw garment crop ───────────────────────
        logger.info(f"Returning raw garment crop for '{name}'")
        return garment_crop

    async def _render_via_gpt_image(
        self,
        client,
        garment_crop_bytes: bytes,
        name: str,
        category: str,
        color_hex: str,
    ) -> bytes | None:
        """
        Send the garment crop to OpenAI gpt-image-1 (image-edit endpoint).
        Returns a clean studio product image: white background, no person.
        """
        import io as _io
        import base64

        # Build a specific, strict prompt
        color_note = f" The exact garment colour is {color_hex}." if color_hex else ""
        prompt = (
            f"You are given a reference photo of a {name} ({category}) being worn. "
            "Generate a realistic, studio-quality e-commerce product image of this exact garment. "
            f"{color_note} "
            "Rules: "
            "1. Plain white (#FFFFFF) background, clean edges. "
            "2. Remove all traces of the human body — no skin, no face, no arms. "
            "3. Preserve the EXACT colour, fabric texture, pattern, buttons, seams, and design. "
            "4. Show the garment centered, slightly floating, in its natural 3D shape. "
            "5. Soft studio lighting from slightly above. "
            "6. Do NOT change colour, design, or add new elements. "
            "Output: a single clean product photo ready for an online fashion store."
        )

        # Prepare image as PNG bytes for the API
        from PIL import Image as _PILImage
        img = _PILImage.open(_io.BytesIO(garment_crop_bytes)).convert("RGBA")
        buf = _io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        # Call gpt-image-1 image edit endpoint
        png_io = _io.BytesIO(png_bytes)
        png_io.name = "garment.png"  # SDK needs a filename for MIME detection

        response = await client.images.edit(
            model="gpt-image-1",
            image=png_io,
            prompt=prompt,
            n=1,
            size="1024x1024",
        )

        # Response comes back as base64-encoded PNG
        b64 = response.data[0].b64_json
        if not b64:
            return None

        result_bytes = base64.b64decode(b64)
        logger.info(f"gpt-image-1 render size: {len(result_bytes)} bytes")
        return result_bytes

    async def _describe_garment(self, client, garment_bytes: bytes) -> str:
        """
        Use GPT-4V to produce a detailed fashion description of a garment.
        E.g. 'orange short-sleeve camp-collar button-up shirt, relaxed fit, textured fabric'.
        """
        try:
            resp = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=80,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": _b64_data_url(garment_bytes),
                                "detail": "high",
                            },
                        },
                        {
                            "type": "text",
                            "text": (
                                "Describe this clothing item for a fashion stylist in 20 words max. "
                                "Include: colour, garment type, collar/neckline, sleeve length, "
                                "fit, and notable fabric/pattern details. "
                                "Example: 'orange short-sleeve camp-collar button-up shirt, "
                                "relaxed fit, textured woven fabric'."
                            ),
                        },
                    ],
                }],
            )
            desc = resp.choices[0].message.content.strip()
            logger.info(f"Garment description: {desc}")
            return desc
        except Exception as exc:
            logger.warning(f"GPT-4V garment description failed: {exc}")
            return ""

    async def _inpaint_outfit(
        self,
        client,
        user_photo_bytes: bytes,
        outfit_description: str,
    ) -> bytes | None:
        """
        DALL-E 2 inpainting — replaces ONLY the clothing on the user's body.

        Uses rembg to find the person's silhouette, then builds a mask that:
        - Keeps the face/head region (top 20% of person bbox) fully opaque
        - Makes the body/clothing region transparent (editable) BUT only
          where the person actually is (follows body contour)
        - Keeps the background fully opaque (unchanged)

        This produces much cleaner results than a crude rectangle mask.
        """
        try:
            import io as _io
            from PIL import Image, ImageDraw, ImageFilter

            # ── Load original image ──────────────────────────────────────────
            img = Image.open(_io.BytesIO(user_photo_bytes)).convert("RGBA")
            w, h = img.size

            # ── Pad to 1024x1024 square ──────────────────────────────────────
            size = max(w, h)
            square = Image.new("RGBA", (size, size), (255, 255, 255, 255))
            offset_x = (size - w) // 2
            offset_y = (size - h) // 2
            square.paste(img, (offset_x, offset_y))
            square = square.resize((1024, 1024), Image.Resampling.LANCZOS)

            # ── Use rembg to get person silhouette ───────────────────────────
            sq_buf = _io.BytesIO()
            square.save(sq_buf, format="PNG")
            sq_bytes = sq_buf.getvalue()

            try:
                from rembg import remove as rembg_remove
                removed = rembg_remove(sq_bytes)
                silhouette = Image.open(_io.BytesIO(removed)).convert("RGBA")
                alpha = silhouette.split()[3]  # Person mask from rembg
            except Exception:
                # Fallback: crude rectangle if rembg fails
                alpha = Image.new("L", (1024, 1024), 0)
                draw_a = ImageDraw.Draw(alpha)
                draw_a.rectangle([256, 0, 768, 1024], fill=255)

            # ── Find person bbox from alpha ──────────────────────────────────
            person_bbox = alpha.getbbox()
            if not person_bbox:
                logger.warning("No person detected in photo for inpainting")
                return None

            _, py0, _, py1 = person_bbox
            person_h = py1 - py0

            # ── Build mask: transparent where clothing is, opaque elsewhere ──
            # Start with all opaque (keep everything)
            mask = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))

            # Where the person IS (alpha > 128) AND below the head (top 20%),
            # make mask transparent (= editable by DALL-E)
            head_cutoff = py0 + int(person_h * 0.20)
            feet_cutoff = py0 + int(person_h * 0.97)

            mask_pixels = mask.load()
            alpha_pixels = alpha.load()
            for y in range(1024):
                for x in range(1024):
                    if head_cutoff < y < feet_cutoff and alpha_pixels[x, y] > 100:
                        mask_pixels[x, y] = (0, 0, 0, 0)  # transparent = edit

            # Slight blur on mask edges for smoother blending
            mask_alpha = mask.split()[3]
            mask_alpha = mask_alpha.filter(ImageFilter.GaussianBlur(radius=3))
            mask.putalpha(mask_alpha)

            # ── Export for API ────────────────────────────────────────────────
            img_buf = _io.BytesIO()
            square.save(img_buf, format="PNG")
            img_bytes = img_buf.getvalue()

            mask_buf = _io.BytesIO()
            mask.save(mask_buf, format="PNG")
            mask_bytes = mask_buf.getvalue()

            prompt = (
                f"Same person wearing {outfit_description[:350]}. "
                "Clothing fits naturally on their body, same pose, same lighting. "
                "Photorealistic fashion photography."
            )[:999]

            logger.info(f"DALL-E 2 inpaint prompt: {prompt}")

            response = await client.images.edit(
                model="dall-e-2",
                image=img_bytes,
                mask=mask_bytes,
                prompt=prompt,
                n=1,
                size="1024x1024",
            )

            image_url = response.data[0].url
            async with httpx.AsyncClient(timeout=90.0) as hc:
                dl = await hc.get(image_url)
                dl.raise_for_status()
                logger.info(f"DALL-E 2 inpaint result: {len(dl.content)} bytes")
                return dl.content

        except Exception as exc:
            logger.error(f"DALL-E 2 inpainting failed: {exc}")
            return None

    async def generate_try_on_image(
        self,
        user_body_bytes: bytes | None,
        garment_attrs: list[dict],
        garment_image_bytes: list[bytes | None] | None = None,
        user_height: int | None = None,
        user_body_type: str | None = None,
    ) -> bytes | None:
        """
        Generate a realistic virtual try-on image.

        Pipeline:
        1. Use GPT-4V on each garment's actual image to get a precise
           fashion description (e.g. "orange camp-collar button-up shirt").
        2. PRIMARY: DALL-E 2 inpainting on the user's actual photo —
           keeps their face/hair/background, replaces only the clothing area.
        3. FALLBACK: DALL-E 3 full-body generation from a rich text prompt
           that describes the user (via GPT-4V) and the exact outfit.

        Args:
            user_body_bytes: User's body photo bytes (for face-preserving inpaint).
            garment_attrs: List of attribute dicts (category, color, name, pattern).
            garment_image_bytes: Matching list of actual garment image bytes.
            user_height: Optional height in cm.
            user_body_type: Optional body type string.

        Returns bytes on success, None if API unavailable.
        """
        client = self._get_client()
        if not client:
            logger.warning("No OpenAI client; skipping DALL-E try-on")
            return None

        try:
            # ── 1. Get precise garment descriptions via GPT-4V ────────────────
            garment_descriptions: list[str] = []
            for i, attrs in enumerate(garment_attrs):
                gb = (garment_image_bytes[i]
                      if garment_image_bytes and i < len(garment_image_bytes)
                      else None)
                if gb:
                    desc = await self._describe_garment(client, gb)
                    if desc:
                        garment_descriptions.append(desc)
                        continue
                # Fallback: build from stored attributes
                color = attrs.get("color_primary") or "neutral"
                name = attrs.get("name") or attrs.get("category", "item")
                pattern = attrs.get("pattern")
                fallback = f"{color} {name}"
                if pattern and pattern not in ("solid", ""):
                    fallback += f", {pattern} pattern"
                garment_descriptions.append(fallback)

            outfit_desc = " and ".join(garment_descriptions) if garment_descriptions else "stylish casual outfit"
            logger.info(f"Final outfit description: {outfit_desc}")

            # ── 2. PRIMARY: DALL-E 2 inpainting (keeps user's face) ───────────
            if user_body_bytes:
                result = await self._inpaint_outfit(client, user_body_bytes, outfit_desc)
                if result:
                    return result
                logger.info("DALL-E 2 inpaint failed, falling back to DALL-E 3 generation")

            # ── 3. FALLBACK: DALL-E 3 full-body generation ────────────────────
            person_desc = "a young adult"
            if user_body_bytes:
                try:
                    desc_resp = await client.chat.completions.create(
                        model="gpt-4o-mini",
                        max_tokens=100,
                        messages=[{
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": _b64_data_url(user_body_bytes),
                                        "detail": "high",
                                    },
                                },
                                {
                                    "type": "text",
                                    "text": (
                                        "Describe this person's physical appearance in 30 words "
                                        "for an artist to recreate them. Include: gender, "
                                        "approximate age, ethnicity/skin tone, hair color + "
                                        "style + length, face shape, build/body type. "
                                        "Do NOT describe clothing."
                                    ),
                                },
                            ],
                        }],
                    )
                    person_desc = desc_resp.choices[0].message.content.strip()
                    logger.info(f"GPT-4V person desc: {person_desc}")
                except Exception as exc:
                    logger.warning(f"Person description failed: {exc}")

            if user_height:
                person_desc += f", approximately {user_height}cm tall"
            if user_body_type:
                person_desc += f", {user_body_type} build"

            prompt = (
                f"A single person: {person_desc}. "
                f"They are wearing exactly: {outfit_desc}. "
                "Standing naturally facing the camera, relaxed confident pose. "
                "Clean neutral studio background. Full body head-to-toe visible. "
                "High-end fashion photography, soft even lighting, sharp focus, "
                "photorealistic. No text, no watermarks."
            )
            logger.info(f"DALL-E 3 fallback prompt: {prompt}")

            response = await client.images.generate(
                model="dall-e-3",
                prompt=prompt,
                size="1024x1792",
                quality="hd",
                n=1,
            )

            image_url = response.data[0].url
            async with httpx.AsyncClient(timeout=90.0) as hc:
                dl = await hc.get(image_url)
                dl.raise_for_status()
                logger.info(f"DALL-E 3 fallback: {len(dl.content)} bytes")
                return dl.content

        except Exception as exc:
            logger.error(f"DALL-E try-on generation failed: {exc}")
            return None

    async def wardrobe_gap_analysis(self, wardrobe_items: list[dict]) -> dict:
        """
        Suggest 3 items that would unlock the most outfit combinations.
        Returns {suggestions: [{item, reason, color}, ...]}.
        """
        client = self._get_client()
        if not client:
            return {"suggestions": []}

        try:
            wardrobe_desc = json.dumps(wardrobe_items, default=str)
            prompt = (
                "Analyze this wardrobe for gaps. What 3 items would unlock the most outfit combinations?\n"
                "Return JSON:\n"
                '{\n'
                '  "suggestions": [\n'
                '    {"item": "description", "reason": "why it helps", "color": "color"},\n'
                '    ...\n'
                '  ]\n'
                '}\n\n'
                f"Wardrobe: {wardrobe_desc}\n\n"
                "Return ONLY JSON, no markdown."
            )

            response = await client.chat.completions.create(
                model="gpt-4o-mini",
                max_tokens=500,
                messages=[{"role": "user", "content": prompt}],
            )

            text = _strip_fences(response.choices[0].message.content)
            result = json.loads(text)
            logger.info(f"Gap analysis: {len(result.get('suggestions', []))} suggestions")
            return result

        except Exception as exc:
            logger.error(f"Gap analysis failed: {exc}")
            return {"suggestions": []}


ai_service = AIService()

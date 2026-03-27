"""
AI service layer — wraps external API calls for:
- Clothing extraction from photos (background removal)
- Dewrinkling / cleaning clothing images
- Color & category detection
- Outfit compatibility scoring (mix-match)
- Virtual try-on image generation
- Shopping recommendations
"""

from app.core.config import settings


class AIService:
    """Singleton-style service for all AI operations."""

    async def extract_clothing(self, image_bytes: bytes) -> bytes:
        """
        Remove background from clothing photo.
        Uses: remove.bg API or rembg (local fallback).
        Returns: PNG bytes with transparent background.
        """
        # TODO: call remove.bg or OpenAI Vision API
        raise NotImplementedError

    async def detect_attributes(self, image_bytes: bytes) -> dict:
        """
        Detect color, category, pattern, etc. from a clothing image.
        Uses: OpenAI Vision API with structured output.
        Returns: {"category": "top", "color_primary": "#1a2b3c", ...}
        """
        # TODO: call OpenAI Vision
        raise NotImplementedError

    async def dewrinkle_image(self, image_bytes: bytes) -> bytes:
        """
        Clean up a clothing photo — straighten, remove wrinkles.
        Uses: image-to-image model or custom pipeline.
        Returns: cleaned PNG bytes.
        """
        # TODO: implement dewrinkling pipeline
        raise NotImplementedError

    async def score_outfit(self, item_image_urls: list[str]) -> float:
        """
        Score how well a set of clothing items go together (0.0 – 1.0).
        Uses: OpenAI Vision or custom embedding similarity.
        """
        # TODO: implement compatibility scoring
        raise NotImplementedError

    async def generate_try_on(self, body_image: bytes, clothing_images: list[bytes]) -> bytes:
        """
        Virtual try-on: composite clothing onto a body photo.
        Uses: pose estimation + garment warping pipeline.
        Returns: composite PNG bytes.
        """
        # TODO: implement try-on pipeline
        raise NotImplementedError

    async def suggest_purchases(self, wardrobe_items: list[dict]) -> list[str]:
        """
        Analyze the wardrobe and suggest items to buy that would
        maximize outfit combinations.
        Returns: list of natural-language suggestions.
        """
        # TODO: implement with OpenAI
        raise NotImplementedError


ai_service = AIService()

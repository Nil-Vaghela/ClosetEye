"""
Outfit suggestions — persistent, wardrobe-aware.

GET  /api/v1/suggestions/        → return saved suggestions (instant, no AI)
POST /api/v1/suggestions/generate → regenerate with AI and save
"""
import hashlib
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.clothing import ClothingItem
from app.models.ai_suggestion import AISuggestion
from app.services.ai_service import ai_service

logger = logging.getLogger(__name__)
router = APIRouter()


def _wardrobe_hash(item_ids: list[str]) -> str:
    """Stable hash of a wardrobe's item IDs — changes when items are added/removed."""
    key = ",".join(sorted(item_ids))
    return hashlib.md5(key.encode()).hexdigest()


async def _fetch_items(db: AsyncSession, user_id) -> list[ClothingItem]:
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == user_id)
    )
    return result.scalars().all()


def _items_to_ai_data(items: list[ClothingItem]) -> list[dict]:
    return [
        {
            "id":            str(item.id),
            "name":          item.name,
            "category":      item.category.value if hasattr(item.category, "value") else str(item.category),
            "color_primary": item.color_primary,
            "color_secondary": item.color_secondary,
            "tags":          item.tags or [],
            "season":        item.season.value if hasattr(item.season, "value") else str(item.season),
        }
        for item in items
    ]


async def _enrich(suggestions: list[dict], items: list[ClothingItem]) -> list[dict]:
    """Attach live image URLs to each suggestion (URLs can change after re-upload)."""
    item_map = {str(i.id): i for i in items}
    rich = []
    for s in suggestions:
        outfit_items = []
        for id_str in s.get("item_ids", []):
            item = item_map.get(str(id_str))
            if item:
                outfit_items.append({
                    "id":        str(item.id),
                    "name":      item.name,
                    "category":  item.category.value if hasattr(item.category, "value") else str(item.category),
                    "color":     item.color_primary,
                    "image_url": item.cleaned_image_url or item.original_image_url,
                })
        rich.append({**s, "items": outfit_items, "item_ids": [i["id"] for i in outfit_items]})
    return rich


# ── GET — return saved suggestions immediately ─────────────────────────────────

@router.get("/")
async def get_suggestions(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Return saved suggestions instantly — no AI call.
    Returns `is_stale=True` if wardrobe changed since last generation,
    so the client can show a "Refresh" banner.
    """
    items = await _fetch_items(db, current_user.id)
    current_hash = _wardrobe_hash([str(i.id) for i in items])

    result = await db.execute(
        select(AISuggestion).where(AISuggestion.owner_id == current_user.id)
    )
    saved = result.scalar_one_or_none()

    if not saved or not saved.suggestions:
        return {
            "outfits": [],
            "is_stale": False,
            "never_generated": True,
            "shopping_suggestions": [],
        }

    # Check if wardrobe changed since last generation
    is_stale = saved.is_stale or (saved.wardrobe_hash != current_hash)

    enriched = await _enrich(saved.suggestions, items)

    return {
        "outfits":              enriched,
        "is_stale":             is_stale,
        "never_generated":      False,
        "generated_at":         saved.generated_at.isoformat(),
        "shopping_suggestions": [],
    }


# ── POST /generate — run AI and save ──────────────────────────────────────────

@router.post("/generate")
async def generate_suggestions(
    occasion: str | None = None,
    season:   str | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Regenerate outfit suggestions with AI and persist them.
    Returns all suggestions (no count limit — saves everything the AI produces).
    """
    items = await _fetch_items(db, current_user.id)
    if not items:
        return {"outfits": [], "is_stale": False, "never_generated": False, "shopping_suggestions": []}

    current_hash = _wardrobe_hash([str(i.id) for i in items])
    items_data   = _items_to_ai_data(items)

    if not season:
        m = datetime.now().month
        season = ("spring" if 3 <= m <= 5 else
                  "summer" if 6 <= m <= 8 else
                  "fall"   if 9 <= m <= 11 else "winter")

    logger.info(f"Generating suggestions for {len(items)} items (occasion={occasion}, season={season})")
    suggestions = await ai_service.suggest_outfits(items_data, occasion=occasion, season=season)

    # Persist / upsert
    result = await db.execute(
        select(AISuggestion).where(AISuggestion.owner_id == current_user.id)
    )
    saved = result.scalar_one_or_none()

    if saved:
        saved.suggestions    = suggestions
        saved.occasion       = occasion
        saved.season         = season
        saved.wardrobe_hash  = current_hash
        saved.is_stale       = False
        saved.generated_at   = datetime.now(timezone.utc)
        saved.updated_at     = datetime.now(timezone.utc)
    else:
        import uuid
        saved = AISuggestion(
            id             = uuid.uuid4(),
            owner_id       = current_user.id,
            suggestions    = suggestions,
            occasion       = occasion,
            season         = season,
            wardrobe_hash  = current_hash,
            is_stale       = False,
        )
        db.add(saved)

    await db.commit()
    logger.info(f"Saved {len(suggestions)} suggestions for user {current_user.id}")

    enriched = await _enrich(suggestions, items)
    return {
        "outfits":              enriched,
        "is_stale":             False,
        "never_generated":      False,
        "generated_at":         saved.generated_at.isoformat(),
        "shopping_suggestions": [],
    }

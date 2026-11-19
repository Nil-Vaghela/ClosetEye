"""
Outfit Engine API Routes
========================
Prefix: /api/v1/outfit

Endpoints:
  GET  /daily                    — get (or generate) today's outfit suggestions
  POST /feedback                 — submit 👍/👎 on an outfit
  POST /wear                     — log that user wore an outfit today
  GET  /history                  — get outfit wear history
  GET  /score                    — compute confidence score for any item combo
  GET  /notifications            — list in-app notifications
  POST /notifications/{id}/read  — mark a notification read
  GET  /notifications/count      — unread count badge
"""
from __future__ import annotations

from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.services import notification_service as ns
from app.services import outfit_engine_service as oe

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Pydantic schemas (inline — keep route file self-contained)
# ─────────────────────────────────────────────────────────────────────────────

class DailyOutfitRequest(BaseModel):
    occasion: Optional[str] = Field(None, description="casual | gym | office | date | travel")
    lat:      Optional[float] = None
    lon:      Optional[float] = None
    force_refresh: bool = False


class FeedbackRequest(BaseModel):
    item_ids:       list[str] = Field(..., min_length=1)
    feedback:       str       = Field(..., pattern="^(like|dislike)$")
    reason:         Optional[str] = None
    daily_outfit_id: Optional[str] = None


class WearRequest(BaseModel):
    item_ids:  list[str] = Field(..., min_length=1)
    worn_date: Optional[str] = Field(None, description="YYYY-MM-DD; defaults to today")
    occasion:  Optional[str] = None
    outfit_id: Optional[str] = None
    note:      Optional[str] = None


class ScoreRequest(BaseModel):
    item_ids:    list[str] = Field(..., min_length=1)
    occasion:    Optional[str] = None
    weather_temp_c: Optional[float] = None


# ─────────────────────────────────────────────────────────────────────────────
# 1. Daily Outfit Engine
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/daily")
async def get_daily_outfits(
    occasion:      Optional[str]   = Query(None, description="casual | gym | office | date | travel"),
    lat:           Optional[float] = Query(None),
    lon:           Optional[float] = Query(None),
    force_refresh: bool            = Query(False),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get today's outfit suggestions for the user.
    - Returns cached result if already generated today for the same occasion
    - Fetches live weather from Open-Meteo if lat/lon provided (no API key required)
    - Generates 1-3 ranked outfit combos with confidence scores and reasons
    """
    result = await oe.get_or_generate_daily_outfits(
        db=db,
        user_id=current_user.id,
        occasion=occasion,
        lat=lat,
        lon=lon,
        force_refresh=force_refresh,
    )

    # Trigger morning notification (idempotent — skipped if already sent today)
    outfit_count = len(result.get("outfits", []))
    await ns.notify_morning_outfit(db, current_user.id, outfit_count)

    # Check and trigger unused item notifications
    await ns.check_and_notify_unused_items(db, current_user.id)

    return result


# ─────────────────────────────────────────────────────────────────────────────
# 2. Confidence Score
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/score")
async def score_outfit(
    payload: ScoreRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Compute a real confidence score for any combination of items.
    Use this in Mix & Match and Try-On screens to show score before try-on.

    Returns:
    {
        "confidence_score": 82,
        "breakdown": { "color": 20, "weather": 22, "occasion": 18, "style": 22 }
    }
    """
    from sqlalchemy import select
    from app.models.clothing import ClothingItem
    from app.models.outfit_engine import UserStylePreferences
    import uuid

    items_result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id.in_([uuid.UUID(iid) for iid in payload.item_ids]),
            ClothingItem.owner_id == current_user.id,
        )
    )
    items = list(items_result.scalars().all())

    if not items:
        raise HTTPException(status_code=404, detail="No matching items found in your wardrobe")

    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == current_user.id)
    )
    prefs = pref_result.scalar_one_or_none()

    return oe.compute_confidence_score(
        items=items,
        weather_temp_c=payload.weather_temp_c,
        occasion=payload.occasion,
        user_prefs=prefs,
    )


# ─────────────────────────────────────────────────────────────────────────────
# 3. Feedback Loop
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/feedback")
async def submit_outfit_feedback(
    payload: FeedbackRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Submit 👍/👎 feedback on an outfit suggestion.
    Automatically updates user's style preference weights.
    """
    return await oe.submit_feedback(
        db=db,
        user_id=current_user.id,
        item_ids=payload.item_ids,
        feedback=payload.feedback,
        reason=payload.reason,
        daily_outfit_id=payload.daily_outfit_id,
    )


# ─────────────────────────────────────────────────────────────────────────────
# 4. Outfit Memory System
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/wear")
async def log_outfit_worn(
    payload: WearRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Log that the user actually wore this outfit.
    - Saves to outfit_history
    - Increments total_wears on each ClothingItem
    - Triggers repetition check notification
    """
    result = await oe.log_worn_outfit(
        db=db,
        user_id=current_user.id,
        item_ids=payload.item_ids,
        worn_date=payload.worn_date,
        occasion=payload.occasion,
        outfit_id=payload.outfit_id,
        note=payload.note,
    )

    # Check for repetition after logging
    await ns.check_and_notify_repetition(db, current_user.id)

    return result


@router.get("/history")
async def get_outfit_history(
    limit: int = Query(30, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get the user's outfit wear history (most recent first).
    Used by Daily Engine to prevent repetition, and by Analytics screen.
    """
    return await oe.get_wear_history(db=db, user_id=current_user.id, limit=limit)


@router.get("/overused")
async def get_overused_items(
    threshold: int = Query(5, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Returns wardrobe items worn more than `threshold` times.
    Useful for the Analytics / Cost Per Wear screen.
    """
    return await oe.get_overused_items(db=db, user_id=current_user.id, threshold=threshold)


# ─────────────────────────────────────────────────────────────────────────────
# 5. Notifications
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/notifications")
async def list_notifications(
    unread_only: bool = Query(False),
    limit: int        = Query(20, le=50),
    db: AsyncSession  = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Poll for in-app notifications. Called on app foreground."""
    return await ns.get_notifications(db, current_user.id, unread_only=unread_only, limit=limit)


@router.get("/notifications/count")
async def unread_notification_count(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return unread notification count for badge display."""
    count = await ns.get_unread_count(db, current_user.id)
    return {"unread_count": count}


@router.post("/notifications/{notification_id}/read")
async def mark_read(
    notification_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark a single notification as read."""
    ok = await ns.mark_notification_read(db, notification_id, current_user.id)
    if not ok:
        raise HTTPException(status_code=404, detail="Notification not found")
    return {"status": "read"}

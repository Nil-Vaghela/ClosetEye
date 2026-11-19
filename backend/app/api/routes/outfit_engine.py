"""
Outfit Engine API Routes
========================
Prefix: /api/v1/outfit

Endpoints:
  GET  /daily                    — get (or generate) today's outfit suggestions
  POST /feedback                 — submit 👍/👎 on an outfit
  POST /wear                     — log that user wore an outfit today
  GET  /history                  — get outfit wear history
  POST /score                    — compute confidence score for any item combo
  GET  /notifications            — list in-app notifications
  POST /notifications/{id}/read  — mark a notification read
  GET  /notifications/count      — unread count badge
"""
from __future__ import annotations

from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.localtime import local_today
from app.models.user import User
from app.services import notification_service as ns
from app.services import outfit_engine_service as oe

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Schemas
# ─────────────────────────────────────────────────────────────────────────────

class FeedbackRequest(BaseModel):
    item_ids:        list[UUID] = Field(..., min_length=1, max_length=8)
    feedback:        str = Field(..., pattern="^(like|dislike|never_pair)$")
    reason:          Optional[str] = Field(None, max_length=500)
    daily_outfit_id: Optional[UUID] = None


class WearRequest(BaseModel):
    item_ids:  list[UUID] = Field(..., min_length=1, max_length=8)
    worn_date: Optional[date] = None
    occasion:  Optional[str] = Field(None, max_length=50)
    outfit_id: Optional[UUID] = None
    note:      Optional[str] = Field(None, max_length=500)


class ScoreRequest(BaseModel):
    item_ids:       list[UUID] = Field(..., min_length=1, max_length=8)
    occasion:       Optional[str] = Field(None, max_length=50)
    weather_temp_c: Optional[float] = Field(None, ge=-60, le=60)


def _unprocessable(exc: ValueError) -> HTTPException:
    return HTTPException(status_code=422, detail=str(exc))


# ─────────────────────────────────────────────────────────────────────────────
# 1. Daily Outfit Engine
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/daily")
async def get_daily_outfits(
    occasion:      Optional[str]   = Query(None, max_length=50),
    lat:           Optional[float] = Query(None, ge=-90, le=90),
    lon:           Optional[float] = Query(None, ge=-180, le=180),
    force_refresh: bool            = Query(False),
    lock:          list[UUID]      = Query(default=[], max_length=4,
                                           description="Item ids to build around"),
    no_repeat_days: int            = Query(oe.DEFAULT_NO_REPEAT_DAYS, ge=0, le=30),
    today: date = Depends(local_today),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Today's outfit suggestions (cached per day + occasion).
    Pass `lock` one or more times to build outfits around specific items.
    Weather comes from Open-Meteo when lat/lon are given (rounded to ~1 km for privacy).
    """
    if lat is not None and lon is not None:
        lat, lon = round(lat, 2), round(lon, 2)
    try:
        result = await oe.get_or_generate_daily_outfits(
            db=db,
            user_id=current_user.id,
            occasion=occasion,
            lat=lat,
            lon=lon,
            force_refresh=force_refresh,
            today=today,
            locked_ids=[str(i) for i in lock],
            no_repeat_days=no_repeat_days,
        )
    except ValueError as exc:
        raise _unprocessable(exc)

    # Idempotent, at most once a day
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
    """Confidence score (0-100) + breakdown for any combination of your items."""
    from sqlalchemy import select
    from app.models.outfit_engine import UserStylePreferences

    try:
        items = await oe._owned_items(db, current_user.id, payload.item_ids)
    except ValueError as exc:
        raise _unprocessable(exc)

    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == current_user.id)
    )
    return oe.compute_confidence_score(
        items=items,
        weather_temp_c=payload.weather_temp_c,
        occasion=payload.occasion,
        user_prefs=pref_result.scalar_one_or_none(),
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
    try:
        return await oe.submit_feedback(
            db=db,
            user_id=current_user.id,
            item_ids=payload.item_ids,
            feedback=payload.feedback,
            reason=payload.reason,
            daily_outfit_id=payload.daily_outfit_id,
        )
    except ValueError as exc:
        raise _unprocessable(exc)


# ─────────────────────────────────────────────────────────────────────────────
# 4. Outfit Memory System
# ─────────────────────────────────────────────────────────────────────────────

@router.post("/wear")
async def log_outfit_worn(
    payload: WearRequest,
    today: date = Depends(local_today),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Log that the user actually wore this outfit.
    - Saves to outfit_history
    - Increments total_wears on each ClothingItem
    - Triggers repetition check notification
    """
    try:
        result = await oe.log_worn_outfit(
            db=db,
            user_id=current_user.id,
            item_ids=payload.item_ids,
            worn_date=payload.worn_date or today,
            occasion=payload.occasion,
            outfit_id=payload.outfit_id,
            note=payload.note,
        )
    except ValueError as exc:
        raise _unprocessable(exc)

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

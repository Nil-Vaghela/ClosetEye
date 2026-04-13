"""
OOTD Log Router
===============
Handle outfit-of-the-day logging for engagement tracking.
"""
import logging
from datetime import date, datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.ootd import OOTDLog
from app.schemas.ootd import OOTDLogCreate, OOTDLogResponse, StreakResponse, CalendarResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("", response_model=OOTDLogResponse, status_code=201)
async def log_ootd(
    payload: OOTDLogCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Log today's outfit (Outfit of The Day).

    Body:
    {
        "outfit_id": "uuid or null" (saved outfit),
        "custom_item_ids": ["uuid1", "uuid2"] (or null),
        "logged_date": "2026-03-31",
        "note": "felt great in this!" (optional)
    }

    Either outfit_id or custom_item_ids must be provided.
    """
    if not payload.outfit_id and not payload.custom_item_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either outfit_id or custom_item_ids must be provided.",
        )

    try:
        log = OOTDLog(
            user_id=current_user.id,
            outfit_id=payload.outfit_id,
            custom_item_ids=payload.custom_item_ids,
            logged_date=payload.logged_date,
            note=payload.note,
        )
        db.add(log)
        await db.commit()
        await db.refresh(log)

        logger.info(f"OOTD logged for user {current_user.id} on {payload.logged_date}")
        return log

    except Exception as exc:
        logger.error(f"Failed to log OOTD: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to log outfit.",
        ) from exc


@router.get("", response_model=list[OOTDLogResponse])
async def list_ootd_history(
    days: int = 90,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List OOTD history for the user (last N days, default 90)."""
    cutoff = date.today() - timedelta(days=days)
    result = await db.execute(
        select(OOTDLog).where(
            OOTDLog.user_id == current_user.id,
            OOTDLog.logged_date >= cutoff,
        ).order_by(OOTDLog.logged_date.desc())
    )
    return result.scalars().all()


@router.get("/streak", response_model=StreakResponse)
async def get_streak(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get current and longest streak of consecutive days with OOTD logged.

    A streak is broken if there's a day with no OOTD.
    """
    result = await db.execute(
        select(OOTDLog.logged_date).where(
            OOTDLog.user_id == current_user.id,
        ).order_by(OOTDLog.logged_date.asc())
    )
    dates = sorted(set(row[0] for row in result))

    if not dates:
        return StreakResponse(current_streak=0, longest_streak=0)

    # Calculate streaks
    current_streak = 0
    longest_streak = 0
    last_date = None

    today = date.today()

    for d in dates:
        if last_date is None:
            current_streak = 1
        elif (d - last_date).days == 1:
            current_streak += 1
        else:
            current_streak = 1

        longest_streak = max(longest_streak, current_streak)
        last_date = d

    # Reset current streak if last date is not today or yesterday
    if last_date != today and (today - last_date).days > 1:
        current_streak = 0

    return StreakResponse(current_streak=current_streak, longest_streak=longest_streak)


@router.get("/calendar", response_model=CalendarResponse)
async def get_calendar(
    year: int,
    month: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get list of dates in a specific month that have OOTD entries.

    Query params:
    - year: e.g. 2026
    - month: e.g. 3 (March)
    """
    if month < 1 or month > 12:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Month must be between 1 and 12.",
        )

    result = await db.execute(
        select(OOTDLog.logged_date).where(
            OOTDLog.user_id == current_user.id,
            func.extract("year", OOTDLog.logged_date) == year,
            func.extract("month", OOTDLog.logged_date) == month,
        ).distinct()
    )

    dates = [row[0] for row in result]
    return CalendarResponse(dates=dates)

"""
Smart Notifications Engine
===========================
Generates and stores in-app notifications. Each type has its own trigger rule.

Types:
  - morning_outfit     : daily outfit is ready (triggered on first GET /outfit/daily)
  - weather_mismatch   : user's recent outfit won't work for today's weather
  - unused_item        : item not worn in N days
  - repetition_warning : user is over-wearing the same item

No external push gateway integrated here — notifications are polled by the
app on startup. Integrate Firebase Cloud Messaging by calling
_send_fcm_notification() when a device token is stored on User.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import and_, select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.clothing import ClothingItem
from app.services.storage import sign_url
from app.models.outfit_engine import NotificationLog, OutfitHistory

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

UNUSED_ITEM_DAYS     = 30   # Alert if item not worn in this many days
REPETITION_THRESHOLD = 3    # Alert if item worn 3+ times in last 14 days
NOTIFICATION_COOLDOWN_HOURS = 23  # Don't re-send same type within this window


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

async def notify_morning_outfit(
    db: AsyncSession,
    user_id: uuid.UUID,
    outfit_count: int,
) -> NotificationLog | None:
    """
    Trigger a 'morning_outfit' notification.
    Skipped if one was sent today already.
    """
    if await _already_sent_today(db, user_id, "morning_outfit"):
        return None

    msg_map = {
        0: "Open the app to build your look for today.",
        1: "We put together 1 outfit idea for you — check it out.",
        2: "We have 2 outfit suggestions ready for you today.",
        3: "3 fresh outfit ideas are waiting for you today.",
    }
    message = msg_map.get(outfit_count, f"{outfit_count} outfit ideas are waiting.")

    return await _create_notification(
        db=db,
        user_id=user_id,
        ntype="morning_outfit",
        title="Your daily outfits are ready ✨",
        message=message,
        payload={"outfit_count": outfit_count},
    )


async def notify_weather_mismatch(
    db: AsyncSession,
    user_id: uuid.UUID,
    temp_c: float,
    condition: str,
    mismatched_items: list[dict],
) -> NotificationLog | None:
    """
    Alert user if their recent outfits won't match today's weather.
    """
    if await _already_sent_today(db, user_id, "weather_mismatch"):
        return None

    if not mismatched_items:
        return None

    item_names = [i.get("name") or i.get("category", "item") for i in mismatched_items[:2]]
    names_str = " and ".join(item_names)

    if temp_c < 10:
        desc = f"It's {temp_c:.0f}°C — a bit cold for {names_str}"
    elif temp_c > 26:
        desc = f"It's {temp_c:.0f}°C — too warm to wear {names_str}"
    else:
        desc = f"Today is {condition}. Your recent outfit might not be ideal."

    return await _create_notification(
        db=db,
        user_id=user_id,
        ntype="weather_mismatch",
        title="Weather heads-up 🌤",
        message=desc,
        payload={"temp_c": temp_c, "condition": condition, "items": mismatched_items},
    )


async def check_and_notify_unused_items(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[NotificationLog]:
    """
    Find items the user hasn't worn in UNUSED_ITEM_DAYS days.
    Creates one notification per unused item (max 2 per day to avoid spam).
    """
    if await _already_sent_today(db, user_id, "unused_item"):
        return []


    # Items with low or zero wears — most likely neglected
    items_result = await db.execute(
        select(ClothingItem).where(
            and_(
                ClothingItem.owner_id == user_id,
                ClothingItem.total_wears == 0,
                ClothingItem.created_at <= datetime.now(timezone.utc) - timedelta(days=UNUSED_ITEM_DAYS),
            )
        ).limit(2)
    )
    unused_items = list(items_result.scalars().all())

    notifications = []
    for item in unused_items:
        name = item.name or item.category or "an item"
        n = await _create_notification(
            db=db,
            user_id=user_id,
            ntype="unused_item",
            title="Forgotten piece in your closet 👕",
            message=f"You haven't worn your {name} yet. Try it in today's outfit!",
            payload={
                "item_id": str(item.id),
                "item_name": name,
                "days_unused": UNUSED_ITEM_DAYS,
                "image_url": item.cleaned_image_url or item.original_image_url,
            },
        )
        notifications.append(n)

    return notifications


async def check_and_notify_repetition(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[NotificationLog]:
    """
    Detect items the user is over-wearing (worn 3+ times in last 14 days).
    """
    if await _already_sent_today(db, user_id, "repetition_warning"):
        return []

    cutoff = date.today() - timedelta(days=14)
    history_result = await db.execute(
        select(OutfitHistory).where(
            and_(
                OutfitHistory.user_id == user_id,
                OutfitHistory.worn_date >= cutoff,
            )
        )
    )
    histories = list(history_result.scalars().all())

    # Count occurrences of each item_id
    from collections import Counter
    item_counter: Counter = Counter()
    for h in histories:
        for iid in (h.item_ids or []):
            item_counter[iid] += 1

    # Find over-worn items
    over_worn_ids = [iid for iid, cnt in item_counter.items() if cnt >= REPETITION_THRESHOLD]
    if not over_worn_ids:
        return []

    # Fetch item details (cap at 1 notification)
    iid_uuid = [uuid.UUID(iid) for iid in over_worn_ids[:1]]
    items_result = await db.execute(
        select(ClothingItem).where(ClothingItem.id.in_(iid_uuid), ClothingItem.owner_id == user_id)
    )
    items = list(items_result.scalars().all())

    notifications = []
    for item in items:
        count = item_counter.get(str(item.id), 0)
        name = item.name or item.category or "this item"
        n = await _create_notification(
            db=db,
            user_id=user_id,
            ntype="repetition_warning",
            title="Time to mix it up 🔄",
            message=f"You've worn your {name} {count} times recently. Your wardrobe has more to offer!",
            payload={
                "item_id": str(item.id),
                "item_name": name,
                "wear_count": count,
                "period_days": 14,
            },
        )
        notifications.append(n)

    return notifications


async def get_notifications(
    db: AsyncSession,
    user_id: uuid.UUID,
    unread_only: bool = False,
    limit: int = 20,
) -> list[dict]:
    """Fetch notifications for a user."""
    stmt = (
        select(NotificationLog)
        .where(NotificationLog.user_id == user_id)
        .order_by(NotificationLog.sent_at.desc())
        .limit(limit)
    )
    if unread_only:
        stmt = stmt.where(NotificationLog.is_read == False)  # noqa: E712

    result = await db.execute(stmt)
    rows = result.scalars().all()
    return [_serialize(n) for n in rows]


async def mark_notification_read(
    db: AsyncSession,
    notification_id: uuid.UUID,
    user_id: uuid.UUID,
) -> bool:
    result = await db.execute(
        select(NotificationLog).where(
            and_(
                NotificationLog.id == notification_id,
                NotificationLog.user_id == user_id,
            )
        )
    )
    n = result.scalar_one_or_none()
    if not n:
        return False
    n.is_read = True
    n.read_at = datetime.now(timezone.utc)
    await db.commit()
    return True


async def get_unread_count(db: AsyncSession, user_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.count()).where(
            and_(
                NotificationLog.user_id == user_id,
                NotificationLog.is_read == False,  # noqa: E712
            )
        )
    )
    return result.scalar_one() or 0


# ─────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

async def _already_sent_today(
    db: AsyncSession,
    user_id: uuid.UUID,
    ntype: str,
) -> bool:
    """Check if a notification of this type was sent in the last COOLDOWN window."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=NOTIFICATION_COOLDOWN_HOURS)
    result = await db.execute(
        select(NotificationLog).where(
            and_(
                NotificationLog.user_id == user_id,
                NotificationLog.notification_type == ntype,
                NotificationLog.sent_at >= cutoff,
            )
        ).limit(1)
    )
    return result.scalar_one_or_none() is not None


async def _create_notification(
    db: AsyncSession,
    user_id: uuid.UUID,
    ntype: str,
    title: str,
    message: str,
    payload: dict,
) -> NotificationLog:
    n = NotificationLog(
        user_id=user_id,
        notification_type=ntype,
        title=title,
        message=message,
        payload=payload,
        sent_at=datetime.now(timezone.utc),
        is_read=False,
    )
    db.add(n)
    await db.commit()
    await db.refresh(n)
    return n


def _serialize(n: NotificationLog) -> dict:
    return {
        "id": str(n.id),
        "type": n.notification_type,
        "title": n.title,
        "message": n.message,
        "payload": {**(n.payload or {}), **(
            {"image_url": sign_url((n.payload or {}).get("image_url"))} if (n.payload or {}).get("image_url") else {}
        )},
        "is_read": n.is_read,
        "sent_at": n.sent_at.isoformat() if n.sent_at else None,
        "read_at": n.read_at.isoformat() if n.read_at else None,
    }

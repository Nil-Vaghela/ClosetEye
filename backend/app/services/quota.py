"""
Cost controls for a free app.

- Every paid AI call is recorded in `ai_usage` with an estimated cost.
- Per-user daily quotas per feature (rolling 24 h).
- Global daily budget: when today's estimated spend reaches DAILY_AI_BUDGET_USD,
  paid features answer "busy, try later" while free features keep working.
- `cached()` stores AI results by content key so repeat views cost nothing.
"""
from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Awaitable, Callable

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.ai_usage import AICache, AIUsage

# feature -> (settings quota attribute, estimated USD per call, friendly limit message)
FEATURES: dict[str, tuple[str, float, str]] = {
    "item_upload": ("QUOTA_ITEM_UPLOADS_PER_DAY", 0.003, "You've added a lot today! Add more tomorrow."),
    "extract":     ("QUOTA_EXTRACT_PER_DAY", 0.03, "You've scanned lots of photos today. More tomorrow!"),
    "tryon":       ("QUOTA_TRYON_PER_DAY", 0.25, "You've used today's try ons. More tomorrow!"),
    "flatlay":     ("QUOTA_FLATLAY_PER_DAY", 0.08, "You've made today's outfit boards. More tomorrow!"),
    "llm":         ("QUOTA_LLM_PER_DAY", 0.01, "Our stylist needs a break. Try again tomorrow!"),
}


# Gemini on Vertex is cheaper per call (approx: flash image ~$0.04/image; flash text fractions of a cent).
_VERTEX_COST: dict[str, float] = {
    "item_upload": 0.002, "extract": 0.01, "tryon": 0.10, "flatlay": 0.04, "llm": 0.005,
}


def _unit_cost(feature: str) -> float:
    from app.services.ai_client import provider
    if provider() == "vertex":
        return _VERTEX_COST[feature]
    return FEATURES[feature][1]


def _quota(feature: str) -> int:
    return int(getattr(settings, FEATURES[feature][0]))


async def spent_today(db: AsyncSession) -> float:
    start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    r = await db.execute(select(func.coalesce(func.sum(AIUsage.cost_estimate), 0.0)).where(AIUsage.created_at >= start))
    return float(r.scalar_one())


async def used_today(db: AsyncSession, user_id: uuid.UUID, feature: str) -> int:
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    r = await db.execute(
        select(func.coalesce(func.sum(AIUsage.units), 0)).where(
            AIUsage.user_id == user_id, AIUsage.feature == feature, AIUsage.created_at >= since
        )
    )
    return int(r.scalar_one())


async def consume(db: AsyncSession, user_id: uuid.UUID, feature: str, units: int = 1,
                  cost: float | None = None) -> None:
    """Check limits and record usage. Raises 429 (user limit) or 503 (global budget)."""
    if feature not in FEATURES:
        raise ValueError(f"unknown feature {feature}")
    _, _, message = FEATURES[feature]
    unit_cost = _unit_cost(feature)
    if await used_today(db, user_id, feature) + units > _quota(feature):
        raise HTTPException(status_code=429, detail=message)
    if await spent_today(db) >= settings.DAILY_AI_BUDGET_USD:
        raise HTTPException(status_code=503, detail="We're really busy right now. Please try again later!")
    db.add(AIUsage(user_id=user_id, feature=feature, units=units,
                   cost_estimate=cost if cost is not None else unit_cost * units))
    await db.commit()


def cache_key(*parts: Any) -> str:
    raw = json.dumps(parts, sort_keys=True, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


async def cached(db: AsyncSession, key: str, max_age: timedelta,
                 produce: Callable[[], Awaitable[Any]]) -> tuple[Any, bool]:
    """Return (value, from_cache). `produce` runs only on a miss."""
    row = await db.get(AICache, key)
    if row and row.created_at and datetime.now(timezone.utc) - row.created_at < max_age:
        return row.value.get("v"), True
    value = await produce()
    if row:
        row.value, row.created_at = {"v": value}, datetime.now(timezone.utc)
    else:
        db.add(AICache(key=key, value={"v": value}))
    await db.commit()
    return value, False

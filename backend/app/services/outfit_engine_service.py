"""
Outfit Engine Service
=====================
Powers:
  1. Daily Outfit Engine  — generates 1-3 outfits per user per day
  2. Confidence Score System — real weighted breakdown (color/weather/occasion/style)
  3. Outfit Memory System — log + query worn history
  4. Feedback Loop — update UserStylePreferences from 👍/👎
  5. Occasion Modes — filter generation rules by mode

Performance targets:
  - < 1.5s for outfit generation (no external calls — pure local logic)
  - Cached daily outfits: if already generated today for same occasion → instant return
"""
from __future__ import annotations

import logging
import random
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from itertools import combinations
from typing import Any

import httpx
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.clothing import ClothingItem, ClothingCategory
from app.models.outfit_engine import (
    DailyOutfit,
    OutfitFeedback,
    OutfitHistory,
    UserStylePreferences,
)

logger = logging.getLogger(__name__)


def _p(a: str, b: str) -> str:
    """Canonical sorted pair key — must be defined before color tables below."""
    return ":".join(sorted([a.lower(), b.lower()]))


# ─────────────────────────────────────────────────────────────────────────────
# Color Harmony Tables
# ─────────────────────────────────────────────────────────────────────────────

# Classic neutral colors that pair with almost anything
_NEUTRALS = {
    "white", "cream", "ivory", "beige", "off-white",
    "black", "charcoal", "slate",
    "navy", "dark navy",
    "grey", "gray", "light grey", "light gray", "dark grey", "dark gray",
    "camel", "tan", "khaki", "sand",
    "brown", "dark brown",
}

# Strong color pairs that are harmonious (sorted tuples → str key)
_HARMONIOUS_PAIRS: set[str] = {
    _p("navy", "white"), _p("navy", "cream"), _p("navy", "beige"),
    _p("black", "white"), _p("black", "red"), _p("black", "gold"),
    _p("white", "red"), _p("white", "blue"), _p("white", "green"),
    _p("grey", "pink"), _p("grey", "yellow"), _p("grey", "blue"),
    _p("beige", "brown"), _p("beige", "camel"), _p("camel", "white"),
    _p("olive", "brown"), _p("olive", "white"), _p("olive", "beige"),
    _p("burgundy", "grey"), _p("burgundy", "cream"), _p("burgundy", "camel"),
    _p("blue", "brown"), _p("blue", "white"), _p("blue", "beige"),
    _p("green", "brown"), _p("green", "camel"), _p("green", "white"),
    _p("mustard", "grey"), _p("mustard", "navy"), _p("mustard", "brown"),
    _p("pink", "grey"), _p("pink", "white"), _p("pink", "navy"),
    _p("red", "navy"), _p("red", "white"), _p("red", "grey"),
    _p("coral", "navy"), _p("coral", "white"), _p("coral", "grey"),
}

# Colors that clash
_CLASHING_PAIRS: set[str] = {
    _p("orange", "red"), _p("orange", "pink"),
    _p("red", "pink"), _p("red", "purple"),
    _p("yellow", "green"), _p("purple", "brown"),
    _p("blue", "green"),  # same spectrum, hard to pull off
}


# ─────────────────────────────────────────────────────────────────────────────
# Occasion Rules
# ─────────────────────────────────────────────────────────────────────────────

_OCCASION_TAG_MAP: dict[str, list[str]] = {
    "casual":   ["casual", "everyday", "relaxed", "streetwear", "weekend"],
    "gym":      ["gym", "athletic", "sport", "activewear", "workout", "training"],
    "office":   ["formal", "business", "office", "professional", "work", "smart"],
    "date":     ["date", "elegant", "romantic", "chic", "dressy", "night out"],
    "travel":   ["travel", "casual", "comfortable", "packable", "lightweight"],
}

_OCCASION_FORBIDDEN_TAGS: dict[str, list[str]] = {
    "gym":    ["formal", "business", "elegant", "dressy"],
    "office": ["gym", "athletic", "sport", "workout"],
    "date":   ["gym", "athletic", "sport"],
}

_OCCASION_REQUIRED_CATEGORIES: dict[str, list[str]] = {
    "gym": ["top"],  # must have a top; allow no jacket
}

# Weather thresholds (°C)
_COLD_MAX    = 10   # below 10°C → need outerwear/heavy fabrics
_COOL_MAX    = 18   # 10-18°C → light jacket optional
_WARM_MAX    = 26   # 18-26°C → light tops; shorts okay
# above 26°C → summer, no heavy layers


# ─────────────────────────────────────────────────────────────────────────────
# Confidence Score Engine
# ─────────────────────────────────────────────────────────────────────────────

def compute_confidence_score(
    items: list[ClothingItem],
    weather_temp_c: float | None,
    occasion: str | None,
    user_prefs: UserStylePreferences | None,
) -> dict[str, Any]:
    """
    Real confidence score — weighted sum of 4 components, max 100.

    Returns:
        {
            "confidence_score": 82,
            "breakdown": { "color": 20, "weather": 22, "occasion": 18, "style": 22 }
        }
    """
    color_score   = _score_color(items)          # 0-25
    weather_score = _score_weather(items, weather_temp_c)  # 0-25
    occasion_score = _score_occasion(items, occasion)       # 0-25
    style_score   = _score_style_consistency(items, user_prefs)  # 0-25

    total = color_score + weather_score + occasion_score + style_score

    return {
        "confidence_score": total,
        "breakdown": {
            "color":   color_score,
            "weather": weather_score,
            "occasion": occasion_score,
            "style":   style_score,
        },
    }


def _score_color(items: list[ClothingItem]) -> int:
    """Score 0–25 based on color harmony between outfit pieces."""
    if not items:
        return 12  # neutral fallback

    colors = []
    for item in items:
        c = item.color_primary
        if c:
            # Strip hex codes — if it starts with #, skip (no name to compare)
            if not c.startswith("#"):
                colors.append(c.lower().strip())

    if len(colors) < 2:
        return 15  # single color — OK, default mid score

    # Check all pairs
    clash_count = 0
    harmony_count = 0
    neutral_count = sum(1 for c in colors if c in _NEUTRALS)
    pair_count = 0

    for a, b in combinations(colors, 2):
        pair_count += 1
        key = _p(a, b)
        if key in _CLASHING_PAIRS:
            clash_count += 1
        elif key in _HARMONIOUS_PAIRS:
            harmony_count += 1

    if pair_count == 0:
        return 15

    # Heavy neutral usage is safe
    neutral_bonus = min(5, neutral_count * 2)
    harmony_ratio = harmony_count / pair_count
    clash_penalty = clash_count * 8

    base = int(harmony_ratio * 20) + neutral_bonus
    score = max(0, min(25, base - clash_penalty))
    return score


def _score_weather(items: list[ClothingItem], temp_c: float | None) -> int:
    """Score 0–25 based on how weather-appropriate the outfit is."""
    if temp_c is None:
        return 18  # unknown weather — give moderate score

    tags_all = []
    seasons_all = []
    categories = []
    for item in items:
        tags_all.extend([t.lower() for t in (item.tags or [])])
        if item.season:
            seasons_all.append(item.season.lower())
        categories.append(item.category.lower() if item.category else "")

    has_outerwear = "outerwear" in categories

    if temp_c < _COLD_MAX:
        # Need warm layers
        warm_tags = {"coat", "jacket", "heavy", "wool", "winter", "warm", "thermal"}
        warm_count = sum(1 for t in tags_all if t in warm_tags)
        if not has_outerwear:
            return max(5, 15 - 5)  # penalize missing jacket
        return min(25, 15 + warm_count * 3)

    elif temp_c < _COOL_MAX:
        # Light jacket or layer is ideal
        cool_tags = {"light jacket", "cardigan", "layer", "spring", "fall"}
        cool_count = sum(1 for t in tags_all if any(ct in t for ct in cool_tags))
        base = 18 if has_outerwear else 14
        return min(25, base + cool_count * 2)

    elif temp_c < _WARM_MAX:
        # Summer-friendly: no heavy winter wear
        winter_tags = {"coat", "heavy", "wool", "winter", "thermal"}
        penalty = sum(1 for t in tags_all if t in winter_tags) * 6
        # Check summer tags
        summer_tags = {"summer", "light", "breathable", "cotton", "linen"}
        bonus = sum(1 for t in tags_all if t in summer_tags) * 2
        return max(0, min(25, 20 + bonus - penalty))

    else:
        # Hot (> 26°C) — penalize heavy items heavily
        hot_penalty_tags = {"coat", "heavy", "wool", "winter", "thermal", "jacket", "sweater"}
        penalty = sum(1 for t in tags_all if t in hot_penalty_tags) * 7
        # Bonus for light summer wear
        summer_tags = {"summer", "light", "shorts", "breathable", "cotton", "linen"}
        bonus = sum(1 for t in tags_all if t in summer_tags) * 2
        return max(0, min(25, 22 + bonus - penalty))


def _score_occasion(items: list[ClothingItem], occasion: str | None) -> int:
    """Score 0–25 based on occasion appropriateness of the outfit."""
    if not occasion:
        return 18  # no occasion set — neutral score

    occ = occasion.lower()
    allowed_tags = _OCCASION_TAG_MAP.get(occ, [])
    forbidden_tags = _OCCASION_FORBIDDEN_TAGS.get(occ, [])

    if not allowed_tags:
        return 18

    tags_all = []
    for item in items:
        tags_all.extend([t.lower() for t in (item.tags or [])])

    match_count = sum(1 for t in tags_all if any(allowed in t for allowed in allowed_tags))
    forbidden_count = sum(1 for t in tags_all if any(forb in t for forb in forbidden_tags))

    base = min(20, match_count * 4)
    penalty = forbidden_count * 7
    return max(0, min(25, base + 5 - penalty))


def _score_style_consistency(
    items: list[ClothingItem],
    user_prefs: UserStylePreferences | None,
) -> int:
    """
    Score 0–25 based on:
    - tags consistency (all casual OR all formal — mixing heavily penalized)
    - user preference weights (liked combos → bonus, disliked → penalty)
    """
    if not items:
        return 12

    # Tag style buckets
    formal_tags = {"formal", "business", "office", "professional", "elegant", "dressy"}
    casual_tags = {"casual", "everyday", "relaxed", "streetwear", "weekend"}
    sport_tags  = {"gym", "athletic", "sport", "activewear"}

    tag_sets = {"formal": 0, "casual": 0, "sport": 0}
    for item in items:
        for t in (item.tags or []):
            tl = t.lower()
            if tl in formal_tags:  tag_sets["formal"] += 1
            if tl in casual_tags:  tag_sets["casual"] += 1
            if tl in sport_tags:   tag_sets["sport"]  += 1

    dominant = max(tag_sets, key=tag_sets.get)
    dominant_count = tag_sets[dominant]
    total_style_tags = sum(tag_sets.values())

    if total_style_tags == 0:
        consistency_score = 12  # no style tags — neutral
    else:
        consistency_ratio = dominant_count / total_style_tags
        consistency_score = int(consistency_ratio * 18)

    # Preference weight bonus/penalty
    pref_adjustment = 0
    if user_prefs:
        colors = [item.color_primary.lower().strip() for item in items
                  if item.color_primary and not item.color_primary.startswith("#")]
        for a, b in combinations(colors, 2):
            key = _p(a, b)
            w = user_prefs.color_pair_weights.get(key, 0.0)
            pref_adjustment += int(w * 7)  # weight -1 to 1 → adjustment -7 to 7

    return max(0, min(25, consistency_score + pref_adjustment))


# ─────────────────────────────────────────────────────────────────────────────
# Weather Fetching
# ─────────────────────────────────────────────────────────────────────────────

async def fetch_weather(lat: float, lon: float) -> dict[str, Any]:
    """
    Fetch current weather from Open-Meteo (free, no API key needed).
    Returns: { temp_c: float, condition: str, description: str }
    """
    url = (
        f"https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lon}"
        f"&current=temperature_2m,weathercode"
        f"&temperature_unit=celsius"
    )
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            data = resp.json()
            temp = data["current"]["temperature_2m"]
            code = data["current"]["weathercode"]
            condition = _wmo_to_condition(code)
            return {"temp_c": temp, "condition": condition, "description": _wmo_description(code)}
    except Exception as e:
        logger.warning(f"Weather fetch failed: {e}")
        return {"temp_c": None, "condition": "unknown", "description": ""}


def _wmo_to_condition(code: int) -> str:
    if code == 0:
        return "sunny"
    if code in (1, 2, 3):
        return "cloudy"
    if code in range(51, 68):
        return "rainy"
    if code in range(71, 78):
        return "snowy"
    if code in range(80, 83):
        return "rainy"
    if code in range(95, 100):
        return "stormy"
    return "cloudy"


def _wmo_description(code: int) -> str:
    descriptions = {
        0: "Clear sky",
        1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        51: "Light drizzle", 53: "Moderate drizzle", 55: "Heavy drizzle",
        61: "Light rain", 63: "Moderate rain", 65: "Heavy rain",
        71: "Light snow", 73: "Moderate snow", 75: "Heavy snow",
        80: "Light showers", 81: "Moderate showers", 82: "Heavy showers",
        95: "Thunderstorm",
    }
    return descriptions.get(code, f"Weather code {code}")


# ─────────────────────────────────────────────────────────────────────────────
# Daily Outfit Engine
# ─────────────────────────────────────────────────────────────────────────────

async def get_or_generate_daily_outfits(
    db: AsyncSession,
    user_id: uuid.UUID,
    occasion: str | None = None,
    lat: float | None = None,
    lon: float | None = None,
    force_refresh: bool = False,
) -> dict[str, Any]:
    """
    Main entry point. Returns up to 3 outfit suggestions for today.

    1. If already generated today (same occasion) → return cached (< 5ms)
    2. Fetch weather if lat/lon provided
    3. Pull wardrobe + worn history + user preferences
    4. Filter + score + rank combinations
    5. Cache in daily_outfits table
    6. Return
    """
    today = date.today()

    # ── Cache check ──────────────────────────────────────────────────────────
    if not force_refresh:
        cached = await _get_cached_daily(db, user_id, today, occasion)
        if cached:
            return {
                "outfits": cached.outfits_json,
                "date": today.isoformat(),
                "cached": True,
                "weather": {
                    "temp_c": cached.weather_temp_c,
                    "condition": cached.weather_condition,
                },
            }

    # ── Weather ──────────────────────────────────────────────────────────────
    weather = {"temp_c": None, "condition": "unknown", "description": ""}
    if lat is not None and lon is not None:
        weather = await fetch_weather(lat, lon)

    temp_c = weather.get("temp_c")

    # ── Wardrobe ─────────────────────────────────────────────────────────────
    items_result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == user_id)
    )
    all_items: list[ClothingItem] = list(items_result.scalars().all())

    if len(all_items) < 2:
        return {
            "outfits": [],
            "date": today.isoformat(),
            "cached": False,
            "message": "Add more items to your wardrobe to get outfit suggestions.",
            "weather": weather,
        }

    # ── Worn history (last 14 days) ───────────────────────────────────────────
    cutoff = today - timedelta(days=14)
    history_result = await db.execute(
        select(OutfitHistory).where(
            and_(
                OutfitHistory.user_id == user_id,
                OutfitHistory.worn_date >= cutoff,
            )
        )
    )
    worn_recently: set[str] = set()
    for h in history_result.scalars().all():
        worn_recently.update(str(iid) for iid in (h.item_ids or []))

    # ── User preferences ──────────────────────────────────────────────────────
    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == user_id)
    )
    user_prefs: UserStylePreferences | None = pref_result.scalar_one_or_none()

    # ── Filter items ──────────────────────────────────────────────────────────
    filtered = _filter_items(all_items, temp_c, occasion, worn_recently)

    # Fallback: if filtering removes too many items, relax the worn_recently constraint
    if _count_by_category(filtered) < 2:
        filtered = _filter_items(all_items, temp_c, occasion, worn_recently=set())

    # ── Build outfit candidates ───────────────────────────────────────────────
    outfits_json = _build_outfits(
        items=filtered,
        all_items=all_items,
        temp_c=temp_c,
        occasion=occasion,
        user_prefs=user_prefs,
        count=3,
    )

    # ── Cache ─────────────────────────────────────────────────────────────────
    daily = DailyOutfit(
        user_id=user_id,
        outfit_date=today,
        occasion=occasion,
        weather_temp_c=temp_c,
        weather_condition=weather.get("condition"),
        outfits_json=outfits_json,
        generated_at=datetime.now(timezone.utc),
    )
    db.add(daily)
    await db.commit()
    await db.refresh(daily)

    return {
        "outfits": outfits_json,
        "date": today.isoformat(),
        "daily_outfit_id": str(daily.id),
        "cached": False,
        "weather": weather,
    }


async def _get_cached_daily(
    db: AsyncSession,
    user_id: uuid.UUID,
    outfit_date: date,
    occasion: str | None,
) -> DailyOutfit | None:
    stmt = select(DailyOutfit).where(
        and_(
            DailyOutfit.user_id == user_id,
            DailyOutfit.outfit_date == outfit_date,
            DailyOutfit.occasion == occasion,
        )
    ).order_by(DailyOutfit.generated_at.desc()).limit(1)
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


def _filter_items(
    items: list[ClothingItem],
    temp_c: float | None,
    occasion: str | None,
    worn_recently: set[str],
) -> list[ClothingItem]:
    """Filter wardrobe items based on weather and occasion rules."""
    filtered = []
    forbidden_tags = _OCCASION_FORBIDDEN_TAGS.get(occasion or "", []) if occasion else []
    allowed_tags   = _OCCASION_TAG_MAP.get(occasion or "", []) if occasion else []

    for item in items:
        item_tags = [t.lower() for t in (item.tags or [])]
        item_id   = str(item.id)

        # Skip recently worn items (soft — they can appear in fallback)
        if item_id in worn_recently:
            continue

        # Occasion filter — skip items with forbidden tags
        if forbidden_tags and any(ft in item_tags for ft in forbidden_tags):
            continue

        # Weather filter — skip heavy coats in summer heat
        if temp_c is not None and temp_c > _WARM_MAX:
            heavy = {"coat", "heavy coat", "puffer", "wool", "thermal"}
            if any(h in item_tags for h in heavy):
                continue

        # Weather filter — skip summer-only in cold
        if temp_c is not None and temp_c < _COLD_MAX:
            summer_only = {"shorts", "tank top", "swimwear"}
            if any(s in item_tags for s in summer_only):
                continue

        filtered.append(item)

    return filtered


def _count_by_category(items: list[ClothingItem]) -> int:
    """Count how many distinct categories are present."""
    return len({item.category for item in items})


def _build_outfits(
    items: list[ClothingItem],
    all_items: list[ClothingItem],
    temp_c: float | None,
    occasion: str | None,
    user_prefs: UserStylePreferences | None,
    count: int = 3,
) -> list[dict]:
    """
    Build outfit combinations from filtered items.
    Groups by category, then tries all valid combinations,
    scores them, returns top N.
    """
    # Bucket by category
    by_cat: dict[str, list[ClothingItem]] = defaultdict(list)
    for item in items:
        by_cat[item.category.lower()].append(item)

    # Build all valid outfit combos
    candidates = []

    tops       = by_cat.get("top", [])
    bottoms    = by_cat.get("bottom", [])
    shoes      = by_cat.get("shoes", [])
    outerwear  = by_cat.get("outerwear", [])
    dresses    = by_cat.get("dress", [])

    # Combo strategy 1: top + bottom + shoes (+ optional jacket)
    if tops and bottoms:
        for top in tops[:6]:  # cap iterations to keep fast
            for bottom in bottoms[:6]:
                shoe_list = shoes[:3] if shoes else [None]
                jkt_list  = outerwear[:2] if outerwear else [None]

                for shoe in shoe_list:
                    for jkt in jkt_list:
                        combo_items = [top, bottom]
                        combo_map: dict[str, str] = {
                            "top":    str(top.id),
                            "bottom": str(bottom.id),
                        }
                        if shoe:
                            combo_items.append(shoe)
                            combo_map["shoes"] = str(shoe.id)
                        if jkt:
                            combo_items.append(jkt)
                            combo_map["jacket"] = str(jkt.id)

                        score_data = compute_confidence_score(combo_items, temp_c, occasion, user_prefs)
                        candidates.append({
                            "items": combo_map,
                            "confidence_score": score_data["confidence_score"],
                            "breakdown": score_data["breakdown"],
                            "reason": _generate_reason(combo_items, score_data, occasion, temp_c),
                        })

    # Combo strategy 2: dress + shoes (+ optional jacket)
    if dresses:
        for dress in dresses[:4]:
            shoe_list = shoes[:2] if shoes else [None]
            jkt_list  = outerwear[:1] if outerwear else [None]

            for shoe in shoe_list:
                for jkt in jkt_list:
                    combo_items = [dress]
                    combo_map = {"dress": str(dress.id)}
                    if shoe:
                        combo_items.append(shoe)
                        combo_map["shoes"] = str(shoe.id)
                    if jkt:
                        combo_items.append(jkt)
                        combo_map["jacket"] = str(jkt.id)

                    score_data = compute_confidence_score(combo_items, temp_c, occasion, user_prefs)
                    candidates.append({
                        "items": combo_map,
                        "confidence_score": score_data["confidence_score"],
                        "breakdown": score_data["breakdown"],
                        "reason": _generate_reason(combo_items, score_data, occasion, temp_c),
                    })

    # Sort by confidence desc, then shuffle top-N pool slightly for variety
    candidates.sort(key=lambda x: x["confidence_score"], reverse=True)

    # Pick top candidates but add slight randomization among top-10 for variety
    top_pool = candidates[:10]
    random.shuffle(top_pool)
    selected = sorted(top_pool[:count], key=lambda x: x["confidence_score"], reverse=True)

    return selected


def _generate_reason(
    items: list[ClothingItem],
    score_data: dict,
    occasion: str | None,
    temp_c: float | None,
) -> str:
    """Generate a human-readable reason for the outfit choice."""
    reasons = []

    bd = score_data.get("breakdown", {})

    if bd.get("color", 0) >= 18:
        colors = [i.color_primary for i in items if i.color_primary and not i.color_primary.startswith("#")]
        if colors:
            reasons.append(f"The {' and '.join(colors[:2])} color combination works well together")

    if bd.get("weather", 0) >= 18 and temp_c is not None:
        if temp_c < _COLD_MAX:
            reasons.append("layered up for cold weather")
        elif temp_c > _WARM_MAX:
            reasons.append("light and breathable for warm weather")
        else:
            reasons.append("perfect for the current temperature")

    if bd.get("occasion", 0) >= 18 and occasion:
        reasons.append(f"fits your {occasion} occasion")

    if bd.get("style", 0) >= 18:
        reasons.append("consistent style across all pieces")

    if not reasons:
        score = score_data.get("confidence_score", 0)
        if score >= 70:
            reasons.append("strong overall outfit combination")
        else:
            reasons.append("a versatile choice from your wardrobe")

    return ". ".join(r.capitalize() for r in reasons[:2]) + "."


# ─────────────────────────────────────────────────────────────────────────────
# Feedback Loop
# ─────────────────────────────────────────────────────────────────────────────

async def submit_feedback(
    db: AsyncSession,
    user_id: uuid.UUID,
    item_ids: list[str],
    feedback: str,  # "like" | "dislike"
    reason: str | None = None,
    daily_outfit_id: str | None = None,
) -> dict[str, Any]:
    """
    Store feedback and update UserStylePreferences weights.
    Weight update uses a simple exponential moving average approach:
      new_weight = old_weight * 0.9 + delta * 0.1
    where delta = +1 for like, -1 for dislike.
    """
    if feedback not in ("like", "dislike"):
        raise ValueError("feedback must be 'like' or 'dislike'")

    # Fetch items to get colors and categories
    items_result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id.in_([uuid.UUID(iid) for iid in item_ids])
        )
    )
    items = list(items_result.scalars().all())

    colors     = [i.color_primary.lower().strip() for i in items if i.color_primary and not i.color_primary.startswith("#")]
    categories = [i.category.lower() for i in items if i.category]

    # Store feedback record
    fb = OutfitFeedback(
        user_id=user_id,
        daily_outfit_id=uuid.UUID(daily_outfit_id) if daily_outfit_id else None,
        item_ids=item_ids,
        color_pair=colors[:4],
        category_pair=categories[:4],
        feedback=feedback,
        reason=reason,
        created_at=datetime.now(timezone.utc),
    )
    db.add(fb)

    # Update or create UserStylePreferences
    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == user_id)
    )
    prefs = pref_result.scalar_one_or_none()

    if prefs is None:
        prefs = UserStylePreferences(
            user_id=user_id,
            color_pair_weights={},
            category_weights={},
            occasion_counts={},
            total_likes=0,
            total_dislikes=0,
            updated_at=datetime.now(timezone.utc),
        )
        db.add(prefs)

    delta = 1.0 if feedback == "like" else -1.0
    decay = 0.85  # how much old weight fades

    # Update color pair weights
    color_weights = dict(prefs.color_pair_weights)
    for a, b in combinations(colors, 2):
        key = _p(a, b)
        old = color_weights.get(key, 0.0)
        color_weights[key] = round(old * decay + delta * (1 - decay), 4)
    prefs.color_pair_weights = color_weights

    # Update category weights
    cat_weights = dict(prefs.category_weights)
    for a, b in combinations(categories, 2):
        key = _p(a, b)
        old = cat_weights.get(key, 0.0)
        cat_weights[key] = round(old * decay + delta * (1 - decay), 4)
    prefs.category_weights = cat_weights

    # Counters
    if feedback == "like":
        prefs.total_likes = (prefs.total_likes or 0) + 1
    else:
        prefs.total_dislikes = (prefs.total_dislikes or 0) + 1

    prefs.updated_at = datetime.now(timezone.utc)

    await db.commit()

    return {
        "status": "ok",
        "message": "Feedback recorded and preferences updated.",
        "total_likes": prefs.total_likes,
        "total_dislikes": prefs.total_dislikes,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Outfit Memory System
# ─────────────────────────────────────────────────────────────────────────────

async def log_worn_outfit(
    db: AsyncSession,
    user_id: uuid.UUID,
    item_ids: list[str],
    worn_date: str | None = None,
    occasion: str | None = None,
    outfit_id: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    """
    Record that the user actually wore this outfit.
    Also increments total_wears on each ClothingItem.
    """
    d = date.fromisoformat(worn_date) if worn_date else date.today()

    # Build snapshot
    item_uuids = [uuid.UUID(iid) for iid in item_ids]
    items_result = await db.execute(
        select(ClothingItem).where(ClothingItem.id.in_(item_uuids))
    )
    items = list(items_result.scalars().all())
    snapshot = {item.category.lower(): str(item.id) for item in items}

    # Log history
    history = OutfitHistory(
        user_id=user_id,
        outfit_id=uuid.UUID(outfit_id) if outfit_id else None,
        items_snapshot=snapshot,
        item_ids=item_ids,
        worn_date=d,
        occasion=occasion,
        note=note,
        created_at=datetime.now(timezone.utc),
    )
    db.add(history)

    # Increment wear count
    for item in items:
        item.total_wears = (item.total_wears or 0) + 1

    await db.commit()

    return {
        "status": "logged",
        "worn_date": d.isoformat(),
        "items_worn": len(items),
        "history_id": str(history.id),
    }


async def get_wear_history(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 30,
) -> list[dict]:
    """Return recent outfit wear history."""
    result = await db.execute(
        select(OutfitHistory)
        .where(OutfitHistory.user_id == user_id)
        .order_by(OutfitHistory.worn_date.desc())
        .limit(limit)
    )
    rows = result.scalars().all()
    return [
        {
            "id": str(h.id),
            "worn_date": h.worn_date.isoformat(),
            "occasion": h.occasion,
            "items_snapshot": h.items_snapshot,
            "item_ids": h.item_ids,
            "note": h.note,
        }
        for h in rows
    ]


async def get_overused_items(
    db: AsyncSession,
    user_id: uuid.UUID,
    threshold: int = 5,
) -> list[dict]:
    """Return items worn more than threshold times."""
    result = await db.execute(
        select(ClothingItem)
        .where(
            and_(
                ClothingItem.owner_id == user_id,
                ClothingItem.total_wears >= threshold,
            )
        )
        .order_by(ClothingItem.total_wears.desc())
    )
    items = result.scalars().all()
    return [
        {
            "id": str(i.id),
            "name": i.name,
            "category": i.category,
            "total_wears": i.total_wears,
            "image_url": i.cleaned_image_url or i.original_image_url,
        }
        for i in items
    ]

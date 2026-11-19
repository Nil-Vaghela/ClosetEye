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

# Generation limits. Pruning keeps 200 item wardrobes well under 300 ms while
# still letting every item compete (no "first N rows only" truncation).
_PAIR_BEAM      = 40   # best top+bottom pairs kept before adding shoes/layers
_SHOES_PER_BASE = 3    # best shoes tried per base
_LAYERS_PER_BASE = 2   # best outerwear tried per base
_MMR_LAMBDA     = 0.7  # relevance vs. diversity trade off
DEFAULT_NO_REPEAT_DAYS = 3


def _cat(item: ClothingItem) -> str:
    c = item.category
    return (c.value if hasattr(c, "value") else str(c or "")).lower()


def _color_name(item: ClothingItem) -> str | None:
    c = item.color_primary
    if not c or c.startswith("#"):
        return None
    return c.lower().strip()


def _pair_key(a: str, b: str) -> str:
    return ":".join(sorted([str(a), str(b)]))


def _blocked_pairs(user_prefs: UserStylePreferences | None) -> set[str]:
    if not user_prefs:
        return set()
    return set(getattr(user_prefs, "blocked_item_pairs", None) or [])


def _has_blocked_pair(items: list[ClothingItem], blocked: set[str]) -> bool:
    if not blocked:
        return False
    ids = [str(i.id) for i in items]
    return any(_pair_key(a, b) in blocked for a, b in combinations(ids, 2))


def _pair_quick_score(a: ClothingItem, b: ClothingItem) -> float:
    """Cheap pairwise score used for pruning before the full scorer runs."""
    ca, cb = _color_name(a), _color_name(b)
    score = 0.5
    if ca and cb:
        key = _p(ca, cb)
        if key in _CLASHING_PAIRS:
            score -= 0.5
        elif key in _HARMONIOUS_PAIRS:
            score += 0.4
        if ca in _NEUTRALS or cb in _NEUTRALS:
            score += 0.2
    ta = {t.lower() for t in (a.tags or [])}
    tb = {t.lower() for t in (b.tags or [])}
    if ta and tb:
        score += 0.3 * len(ta & tb) / len(ta | tb)
    return score


def _needs_layer(temp_c: float | None) -> bool | None:
    """True = add outerwear, False = never, None = unknown weather (offer both)."""
    if temp_c is None:
        return None
    return temp_c < _COOL_MAX


def _build_outfits(
    items: list[ClothingItem],
    all_items: list[ClothingItem],
    temp_c: float | None,
    occasion: str | None,
    user_prefs: UserStylePreferences | None,
    count: int = 3,
    locked_ids: set[str] | None = None,
    worn_recently: set[str] | None = None,
    seed: int | None = None,
) -> list[dict]:
    """
    Build, score and pick `count` diverse outfits.

    Templates: top + bottom (+ shoes) (+ outerwear when cold) and
    dress (+ shoes) (+ outerwear when cold). Locked items must appear in every
    result. Pairs the user blocked ("never pair these") are never returned.
    Recently worn items get a freshness penalty instead of a hard exclusion.
    """
    locked_ids = locked_ids or set()
    worn_recently = worn_recently or set()
    blocked = _blocked_pairs(user_prefs)
    rng = random.Random(seed)

    pool = {str(i.id): i for i in items}
    for i in all_items:  # locked items are always eligible, even if filtered out
        if str(i.id) in locked_ids:
            pool[str(i.id)] = i

    by_cat: dict[str, list[ClothingItem]] = defaultdict(list)
    for item in pool.values():
        by_cat[_cat(item)].append(item)

    def restrict(cat: str) -> list[ClothingItem]:
        locked_here = [i for i in by_cat.get(cat, []) if str(i.id) in locked_ids]
        return locked_here or by_cat.get(cat, [])

    tops, bottoms = restrict("top"), restrict("bottom")
    shoes, layers, dresses = restrict("shoes"), restrict("outerwear"), restrict("dress")
    locked_cats = {_cat(pool[i]) for i in locked_ids if i in pool}

    # ── Bases ────────────────────────────────────────────────────────────────
    bases: list[tuple[float, list[ClothingItem]]] = []
    if "dress" not in locked_cats and tops and bottoms:
        for t in tops:
            for b in bottoms:
                if _has_blocked_pair([t, b], blocked):
                    continue
                bases.append((_pair_quick_score(t, b) + rng.random() * 0.05, [t, b]))
    if not ({"top", "bottom"} & locked_cats):
        for d in dresses:
            bases.append((0.6 + rng.random() * 0.05, [d]))
    bases.sort(key=lambda x: x[0], reverse=True)
    bases = bases[:_PAIR_BEAM]

    def best_for(base: list[ClothingItem], options: list[ClothingItem], k: int) -> list[ClothingItem]:
        scored = []
        for o in options:
            if _has_blocked_pair(base + [o], blocked):
                continue
            s = sum(_pair_quick_score(o, x) for x in base) / len(base)
            scored.append((s, o))
        scored.sort(key=lambda x: x[0], reverse=True)
        return [o for _, o in scored[:k]]

    layer_rule = _needs_layer(temp_c)
    must_layer = "outerwear" in locked_cats

    candidates: list[dict] = []
    for _, base in bases:
        shoe_opts: list[ClothingItem | None] = best_for(base, shoes, _SHOES_PER_BASE) or [None]
        if must_layer:
            layer_opts: list[ClothingItem | None] = best_for(base, layers, _LAYERS_PER_BASE)
        elif layer_rule is True:
            layer_opts = best_for(base, layers, _LAYERS_PER_BASE) or [None]
        elif layer_rule is False:
            layer_opts = [None]
        else:
            layer_opts = [None] + best_for(base, layers, 1)
        if not layer_opts:
            continue

        for shoe in shoe_opts:
            for layer in layer_opts:
                combo = list(base)
                if shoe:
                    combo.append(shoe)
                if layer:
                    combo.append(layer)
                ids = {str(i.id) for i in combo}
                if not locked_ids <= ids or _has_blocked_pair(combo, blocked):
                    continue

                score_data = compute_confidence_score(combo, temp_c, occasion, user_prefs)
                fresh_penalty = 6 * sum(1 for i in ids if i in worn_recently and i not in locked_ids)
                final = max(0, score_data["confidence_score"] - fresh_penalty)

                combo_map: dict[str, str] = {}
                for item in combo:
                    slot = "jacket" if _cat(item) == "outerwear" else _cat(item)
                    combo_map[slot] = str(item.id)

                candidates.append({
                    "items": combo_map,
                    "item_ids": [str(i.id) for i in combo],
                    "confidence_score": final,
                    "breakdown": score_data["breakdown"],
                    "reason": _generate_reason(combo, score_data, occasion, temp_c),
                })

    return _select_diverse(candidates, count, locked_ids)


def _select_diverse(candidates: list[dict], count: int, locked_ids: set[str]) -> list[dict]:
    """Maximal marginal relevance: high score, low item overlap with picks so far."""
    if not candidates:
        return []
    remaining = sorted(candidates, key=lambda c: c["confidence_score"], reverse=True)[:200]
    selected: list[dict] = []
    while remaining and len(selected) < count:
        best, best_val = None, None
        for c in remaining:
            ids = set(c["item_ids"]) - locked_ids
            overlap = 0.0
            for s in selected:
                sids = set(s["item_ids"]) - locked_ids
                if ids or sids:
                    overlap = max(overlap, len(ids & sids) / max(1, len(ids | sids)))
            val = _MMR_LAMBDA * (c["confidence_score"] / 100) - (1 - _MMR_LAMBDA) * overlap
            if best_val is None or val > best_val:
                best, best_val = c, val
        selected.append(best)
        remaining.remove(best)
    return selected


async def get_or_generate_daily_outfits(
    db: AsyncSession,
    user_id: uuid.UUID,
    occasion: str | None = None,
    lat: float | None = None,
    lon: float | None = None,
    force_refresh: bool = False,
    today: date | None = None,
    locked_ids: list[str] | None = None,
    no_repeat_days: int = DEFAULT_NO_REPEAT_DAYS,
) -> dict[str, Any]:
    """
    Returns up to 3 outfit suggestions for the user's local `today`.
    Cached per (user, date, occasion) unless items changed, locks are given,
    or a refresh is forced.
    """
    today = today or date.today()
    locked = {str(i) for i in (locked_ids or [])}

    items_result = await db.execute(select(ClothingItem).where(ClothingItem.owner_id == user_id))
    all_items: list[ClothingItem] = list(items_result.scalars().all())
    owned_ids = {str(i.id) for i in all_items}

    if not locked <= owned_ids:
        raise ValueError("Some locked items aren't in your wardrobe.")

    # ── Cache check ──────────────────────────────────────────────────────────
    if not force_refresh and not locked:
        cached = await _get_cached_daily(db, user_id, today, occasion)
        if cached and _cache_still_valid(cached.outfits_json, owned_ids):
            return {
                "outfits": cached.outfits_json,
                "date": today.isoformat(),
                "daily_outfit_id": str(cached.id),
                "cached": True,
                "weather": {
                    "temp_c": cached.weather_temp_c,
                    "condition": cached.weather_condition or "unknown",
                    "description": "",
                },
            }

    weather = {"temp_c": None, "condition": "unknown", "description": ""}
    if lat is not None and lon is not None:
        weather = await fetch_weather(lat, lon)
    temp_c = weather.get("temp_c")

    if len(all_items) < 2:
        return {
            "outfits": [],
            "date": today.isoformat(),
            "cached": False,
            "message": "Add a few more pieces to your closet and we'll start styling you.",
            "weather": weather,
        }

    cutoff = today - timedelta(days=max(0, no_repeat_days))
    history_result = await db.execute(
        select(OutfitHistory).where(
            and_(OutfitHistory.user_id == user_id, OutfitHistory.worn_date >= cutoff)
        )
    )
    worn_recently: set[str] = set()
    for h in history_result.scalars().all():
        worn_recently.update(str(iid) for iid in (h.item_ids or []))

    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == user_id)
    )
    user_prefs = pref_result.scalar_one_or_none()

    filtered = _filter_items(all_items, temp_c, occasion, worn_recently=set())
    # Seed varies per user per day (and per refresh) so suggestions rotate.
    seed = hash((str(user_id), today.isoformat(), occasion, datetime.now().timestamp() if force_refresh else 0))
    outfits_json = _build_outfits(
        items=filtered,
        all_items=all_items,
        temp_c=temp_c,
        occasion=occasion,
        user_prefs=user_prefs,
        count=3,
        locked_ids=locked,
        worn_recently=worn_recently,
        seed=seed,
    )
    if not outfits_json and filtered is not all_items:
        outfits_json = _build_outfits(
            items=all_items, all_items=all_items, temp_c=temp_c, occasion=occasion,
            user_prefs=user_prefs, count=3, locked_ids=locked,
            worn_recently=worn_recently, seed=seed,
        )

    result: dict[str, Any] = {
        "outfits": outfits_json,
        "date": today.isoformat(),
        "cached": False,
        "weather": weather,
    }
    if not outfits_json:
        result["message"] = "We need at least a top and a bottom (or a dress) to build a look."

    if locked:  # "build around this" results are not the daily pick, don't cache
        return result

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
    result["daily_outfit_id"] = str(daily.id)
    return result


def _cache_still_valid(outfits_json: list | dict, owned_ids: set[str]) -> bool:
    if not isinstance(outfits_json, list):
        return False
    for o in outfits_json:
        ids = o.get("item_ids") or list((o.get("items") or {}).values())
        if not set(ids) <= owned_ids:
            return False
    return True


async def _get_cached_daily(
    db: AsyncSession,
    user_id: uuid.UUID,
    outfit_date: date,
    occasion: str | None,
) -> DailyOutfit | None:
    occ_filter = DailyOutfit.occasion.is_(None) if occasion is None else DailyOutfit.occasion == occasion
    stmt = (
        select(DailyOutfit)
        .where(DailyOutfit.user_id == user_id, DailyOutfit.outfit_date == outfit_date, occ_filter)
        .order_by(DailyOutfit.generated_at.desc())
        .limit(1)
    )
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


def _filter_items(
    items: list[ClothingItem],
    temp_c: float | None,
    occasion: str | None,
    worn_recently: set[str],
) -> list[ClothingItem]:
    """Hard filters: occasion-forbidden tags and clearly wrong weather pieces."""
    filtered = []
    forbidden_tags = _OCCASION_FORBIDDEN_TAGS.get(occasion or "", []) if occasion else []

    for item in items:
        item_tags = [t.lower() for t in (item.tags or [])]
        if str(item.id) in worn_recently:
            continue
        if forbidden_tags and any(ft in item_tags for ft in forbidden_tags):
            continue
        if temp_c is not None and temp_c > _WARM_MAX:
            heavy = {"coat", "heavy coat", "puffer", "wool", "thermal"}
            if any(h in item_tags for h in heavy):
                continue
        if temp_c is not None and temp_c < _COLD_MAX:
            summer_only = {"shorts", "tank top", "swimwear"}
            if any(s in item_tags for s in summer_only):
                continue
        filtered.append(item)
    return filtered


def _generate_reason(
    items: list[ClothingItem],
    score_data: dict,
    occasion: str | None,
    temp_c: float | None,
) -> str:
    """Short, human explanation for the outfit choice."""
    reasons = []
    bd = score_data.get("breakdown", {})

    if bd.get("color", 0) >= 18:
        colors = [c for c in (_color_name(i) for i in items) if c]
        if len(colors) >= 2:
            reasons.append(f"{colors[0]} and {colors[1]} look great together")
    if bd.get("weather", 0) >= 18 and temp_c is not None:
        if temp_c < _COLD_MAX:
            reasons.append("layered up for the cold")
        elif temp_c > _WARM_MAX:
            reasons.append("light and breezy for the heat")
        else:
            reasons.append("just right for today's weather")
    if bd.get("occasion", 0) >= 18 and occasion:
        reasons.append(f"made for {occasion}")
    if bd.get("style", 0) >= 18:
        reasons.append("every piece shares the same vibe")
    if not reasons:
        reasons.append("an easy, versatile pick from your closet")
    return ". ".join(r[0].upper() + r[1:] for r in reasons[:2]) + "."


# ─────────────────────────────────────────────────────────────────────────────
# Feedback Loop
# ─────────────────────────────────────────────────────────────────────────────

async def _owned_items(db: AsyncSession, user_id: uuid.UUID, item_ids: list[uuid.UUID]) -> list[ClothingItem]:
    """Load items by id, only if every id belongs to the user. Raises ValueError otherwise."""
    unique = list(dict.fromkeys(item_ids))
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.id.in_(unique), ClothingItem.owner_id == user_id)
    )
    items = list(result.scalars().all())
    if len(items) != len(unique):
        raise ValueError("Some of those items aren't in your closet.")
    return items


async def submit_feedback(
    db: AsyncSession,
    user_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    feedback: str,  # "like" | "dislike" | "never_pair"
    reason: str | None = None,
    daily_outfit_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    """
    Store feedback and update the user's learned weights.
    `never_pair` additionally blocks every item pair in the outfit from future suggestions.
    """
    if feedback not in ("like", "dislike", "never_pair"):
        raise ValueError("feedback must be like, dislike or never_pair")

    items = await _owned_items(db, user_id, item_ids)

    if daily_outfit_id is not None:
        owns = await db.execute(
            select(DailyOutfit.id).where(DailyOutfit.id == daily_outfit_id, DailyOutfit.user_id == user_id)
        )
        if owns.scalar_one_or_none() is None:
            daily_outfit_id = None

    colors = [c for c in (_color_name(i) for i in items) if c]
    categories = [_cat(i) for i in items]

    db.add(OutfitFeedback(
        user_id=user_id,
        daily_outfit_id=daily_outfit_id,
        item_ids=[str(i.id) for i in items],
        color_pair=colors[:4],
        category_pair=categories[:4],
        feedback=feedback,
        reason=reason,
        created_at=datetime.now(timezone.utc),
    ))

    pref_result = await db.execute(
        select(UserStylePreferences).where(UserStylePreferences.user_id == user_id)
    )
    prefs = pref_result.scalar_one_or_none()
    if prefs is None:
        prefs = UserStylePreferences(
            user_id=user_id, color_pair_weights={}, category_weights={},
            occasion_counts={}, blocked_item_pairs=[], total_likes=0, total_dislikes=0,
            updated_at=datetime.now(timezone.utc),
        )
        db.add(prefs)

    delta = 1.0 if feedback == "like" else -1.0
    decay = 0.85

    color_weights = dict(prefs.color_pair_weights or {})
    for a, b in combinations(colors, 2):
        key = _p(a, b)
        color_weights[key] = round(color_weights.get(key, 0.0) * decay + delta * (1 - decay), 4)
    prefs.color_pair_weights = color_weights

    cat_weights = dict(prefs.category_weights or {})
    for a, b in combinations(categories, 2):
        key = _p(a, b)
        cat_weights[key] = round(cat_weights.get(key, 0.0) * decay + delta * (1 - decay), 4)
    prefs.category_weights = cat_weights

    if feedback == "never_pair":
        blocked = set(prefs.blocked_item_pairs or [])
        for a, b in combinations([str(i.id) for i in items], 2):
            blocked.add(_pair_key(a, b))
        prefs.blocked_item_pairs = sorted(blocked)

    if feedback == "like":
        prefs.total_likes = (prefs.total_likes or 0) + 1
    else:
        prefs.total_dislikes = (prefs.total_dislikes or 0) + 1
    prefs.updated_at = datetime.now(timezone.utc)

    await db.commit()
    return {
        "status": "ok",
        "message": "Thanks! We'll keep learning your style.",
        "total_likes": prefs.total_likes,
        "total_dislikes": prefs.total_dislikes,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Outfit Memory System
# ─────────────────────────────────────────────────────────────────────────────

async def log_worn_outfit(
    db: AsyncSession,
    user_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    worn_date: date | None = None,
    occasion: str | None = None,
    outfit_id: uuid.UUID | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    """
    Record that the user wore these items. Updates wear counts and also writes
    the OOTD log so streaks and the calendar count it.
    """
    from app.models.ootd import OOTDLog
    from app.models.outfit import Outfit

    d = worn_date or date.today()
    items = await _owned_items(db, user_id, item_ids)

    if outfit_id is not None:
        owns = await db.execute(select(Outfit.id).where(Outfit.id == outfit_id, Outfit.owner_id == user_id))
        if owns.scalar_one_or_none() is None:
            raise ValueError("That outfit isn't yours.")

    snapshot: dict[str, Any] = {}
    for item in items:
        snapshot.setdefault(_cat(item), [])
        snapshot[_cat(item)].append(str(item.id))

    ids = [str(i.id) for i in items]
    history = OutfitHistory(
        user_id=user_id,
        outfit_id=outfit_id,
        items_snapshot=snapshot,
        item_ids=ids,
        worn_date=d,
        occasion=occasion,
        note=note,
        created_at=datetime.now(timezone.utc),
    )
    db.add(history)
    db.add(OOTDLog(
        user_id=user_id,
        outfit_id=outfit_id,
        custom_item_ids=None if outfit_id else [i.id for i in items],
        logged_date=d,
        note=note,
    ))

    for item in items:
        item.total_wears = (item.total_wears or 0) + 1

    await db.commit()
    return {
        "status": "logged",
        "worn_date": d.isoformat(),
        "items_worn": len(items),
        "history_id": str(history.id),
    }


async def get_wear_history(db: AsyncSession, user_id: uuid.UUID, limit: int = 30) -> list[dict]:
    result = await db.execute(
        select(OutfitHistory)
        .where(OutfitHistory.user_id == user_id)
        .order_by(OutfitHistory.worn_date.desc(), OutfitHistory.created_at.desc())
        .limit(limit)
    )
    return [
        {
            "id": str(h.id),
            "worn_date": h.worn_date.isoformat(),
            "occasion": h.occasion,
            "items_snapshot": h.items_snapshot,
            "item_ids": h.item_ids,
            "note": h.note,
        }
        for h in result.scalars().all()
    ]


async def get_overused_items(db: AsyncSession, user_id: uuid.UUID, threshold: int = 5) -> list[dict]:
    result = await db.execute(
        select(ClothingItem)
        .where(and_(ClothingItem.owner_id == user_id, ClothingItem.total_wears >= threshold))
        .order_by(ClothingItem.total_wears.desc())
    )
    return [
        {
            "id": str(i.id),
            "name": i.name,
            "category": _cat(i),
            "total_wears": i.total_wears,
            "image_url": i.cleaned_image_url or i.original_image_url,
        }
        for i in result.scalars().all()
    ]

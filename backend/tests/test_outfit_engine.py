import random
import time
import uuid
from types import SimpleNamespace

from app.services import outfit_engine_service as oe
from tests.conftest import auth, make_item, make_user


def fake_item(cat, color=None, tags=None):
    return SimpleNamespace(
        id=uuid.uuid4(), category=cat, color_primary=color, tags=tags or [],
        season="all", name=f"{color} {cat}",
    )


def wardrobe(n_tops=3, n_bottoms=3, n_shoes=2, n_jackets=1):
    colors = ["navy", "white", "black", "grey", "beige", "olive", "red", "camel"]
    items = []
    for cat, n in (("top", n_tops), ("bottom", n_bottoms), ("shoes", n_shoes), ("outerwear", n_jackets)):
        items += [fake_item(cat, colors[i % len(colors)], ["casual"]) for i in range(n)]
    return items


# ── Pure engine ──────────────────────────────────────────────────────────────

def test_no_jacket_when_hot():
    items = wardrobe()
    outfits = oe._build_outfits(items, items, temp_c=30, occasion=None, user_prefs=None, seed=1)
    assert outfits
    assert all("jacket" not in o["items"] for o in outfits)


def test_jacket_when_cold():
    items = wardrobe()
    outfits = oe._build_outfits(items, items, temp_c=5, occasion=None, user_prefs=None, seed=1)
    assert outfits and all("jacket" in o["items"] for o in outfits)


def test_every_item_can_be_used_in_large_wardrobe():
    """Old engine only looked at the first 6 tops; the 20th top must be reachable."""
    items = wardrobe(n_tops=20, n_bottoms=2, n_shoes=1, n_jackets=0)
    star = fake_item("top", "white", ["casual"])
    bottoms = [i for i in items if i.category == "bottom"]
    for b in bottoms:
        b.color_primary = "navy"
    for t in items:
        if t.category == "top":
            t.color_primary = "red"  # clash-free but not harmonious with navy+... keep worse than star
            t.tags = []
    items.append(star)
    outfits = oe._build_outfits(items, items, temp_c=20, occasion=None, user_prefs=None, seed=3)
    assert any(o["items"].get("top") == str(star.id) for o in outfits)


def test_results_are_diverse():
    items = wardrobe(n_tops=5, n_bottoms=5, n_shoes=3, n_jackets=0)
    outfits = oe._build_outfits(items, items, temp_c=20, occasion=None, user_prefs=None, count=3, seed=2)
    assert len(outfits) == 3
    bases = {(o["items"].get("top"), o["items"].get("bottom")) for o in outfits}
    assert len(bases) == 3


def test_locked_item_in_every_outfit():
    items = wardrobe(n_tops=4, n_bottoms=4, n_shoes=2, n_jackets=0)
    locked = next(i for i in items if i.category == "bottom")
    outfits = oe._build_outfits(items, items, 20, None, None, locked_ids={str(locked.id)}, seed=4)
    assert outfits and all(o["items"]["bottom"] == str(locked.id) for o in outfits)


def test_never_pair_is_respected():
    items = wardrobe(n_tops=1, n_bottoms=2, n_shoes=1, n_jackets=0)
    top = items[0]
    b1, b2 = [i for i in items if i.category == "bottom"]
    prefs = SimpleNamespace(color_pair_weights={}, blocked_item_pairs=[oe._pair_key(str(top.id), str(b1.id))])
    outfits = oe._build_outfits(items, items, 20, None, prefs, seed=5)
    assert outfits and all(o["items"]["bottom"] == str(b2.id) for o in outfits)


def test_dress_template():
    items = [fake_item("dress", "black"), fake_item("shoes", "white")]
    outfits = oe._build_outfits(items, items, 22, None, None, seed=6)
    assert outfits and set(outfits[0]["items"]) == {"dress", "shoes"}


def test_200_items_under_300ms():
    rnd = random.Random(0)
    colors = ["navy", "white", "black", "grey", "beige", "olive", "red", "camel", "pink", "blue"]
    cats = ["top"] * 70 + ["bottom"] * 50 + ["shoes"] * 30 + ["outerwear"] * 25 + ["dress"] * 25
    items = [fake_item(c, rnd.choice(colors), rnd.sample(["casual", "formal", "office", "summer", "wool"], 2)) for c in cats]
    for temp in (None, 5, 30):
        t0 = time.perf_counter()
        out = oe._build_outfits(items, items, temp, "office", None, seed=7)
        elapsed = time.perf_counter() - t0
        assert out and elapsed < 0.3, f"{elapsed:.3f}s at temp={temp}"


# ── API ──────────────────────────────────────────────────────────────────────

async def test_daily_endpoint_and_cache(client, db):
    u = await make_user(db)
    for cat, color in (("top", "white"), ("bottom", "navy"), ("shoes", "black")):
        await make_item(db, u, cat, color)
    r = await client.get("/api/v1/outfit/daily", headers=auth(u))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["outfits"] and body["daily_outfit_id"] and body["cached"] is False
    r2 = await client.get("/api/v1/outfit/daily", headers=auth(u))
    assert r2.json()["cached"] is True and r2.json()["daily_outfit_id"] == body["daily_outfit_id"]


async def test_wear_rejects_other_users_items(client, db):
    alice, bob = await make_user(db), await make_user(db)
    bobs = await make_item(db, bob, "top", "red")
    r = await client.post("/api/v1/outfit/wear", headers=auth(alice), json={"item_ids": [str(bobs.id)]})
    assert r.status_code == 422
    await db.refresh(bobs)
    assert bobs.total_wears == 0


async def test_feedback_rejects_other_users_items(client, db):
    alice, bob = await make_user(db), await make_user(db)
    bobs = await make_item(db, bob, "top", "red")
    r = await client.post("/api/v1/outfit/feedback", headers=auth(alice),
                          json={"item_ids": [str(bobs.id)], "feedback": "like"})
    assert r.status_code == 422


async def test_bad_ids_are_422_not_500(client, db):
    u = await make_user(db)
    r = await client.post("/api/v1/outfit/wear", headers=auth(u), json={"item_ids": ["not-a-uuid"]})
    assert r.status_code == 422
    r = await client.post("/api/v1/outfit/feedback", headers=auth(u),
                          json={"item_ids": [str(uuid.uuid4())], "feedback": "like",
                                "daily_outfit_id": str(uuid.uuid4())})
    assert r.status_code == 422


async def test_wearing_counts_toward_streak(client, db):
    u = await make_user(db)
    t = await make_item(db, u, "top", "white")
    r = await client.post("/api/v1/outfit/wear", headers=auth(u), json={"item_ids": [str(t.id)]})
    assert r.status_code == 200, r.text
    s = await client.get("/api/v1/ootd/streak", headers=auth(u))
    assert s.json()["current_streak"] == 1
    await db.refresh(t)
    assert t.total_wears == 1


async def test_never_pair_feedback_blocks_future(client, db):
    u = await make_user(db)
    top = await make_item(db, u, "top", "white")
    b1 = await make_item(db, u, "bottom", "navy")
    b2 = await make_item(db, u, "bottom", "black")
    r = await client.post("/api/v1/outfit/feedback", headers=auth(u),
                          json={"item_ids": [str(top.id), str(b1.id)], "feedback": "never_pair"})
    assert r.status_code == 200, r.text
    r = await client.get("/api/v1/outfit/daily?force_refresh=true", headers=auth(u))
    outs = r.json()["outfits"]
    assert outs and all(o["items"]["bottom"] == str(b2.id) for o in outs)


async def test_lock_param(client, db):
    u = await make_user(db)
    await make_item(db, u, "top", "white")
    await make_item(db, u, "top", "grey")
    b = await make_item(db, u, "bottom", "navy")
    await make_item(db, u, "bottom", "black")
    r = await client.get(f"/api/v1/outfit/daily?lock={b.id}", headers=auth(u))
    assert r.status_code == 200
    assert all(o["items"]["bottom"] == str(b.id) for o in r.json()["outfits"])
    other = await make_user(db)
    foreign = await make_item(db, other, "top", "red")
    r = await client.get(f"/api/v1/outfit/daily?lock={foreign.id}", headers=auth(u))
    assert r.status_code == 422


async def test_cache_invalidated_when_item_deleted(client, db):
    u = await make_user(db)
    t = await make_item(db, u, "top", "white")
    await make_item(db, u, "bottom", "navy")
    await make_item(db, u, "top", "grey")
    first = (await client.get("/api/v1/outfit/daily", headers=auth(u))).json()
    used_top = first["outfits"][0]["items"]["top"]
    r = await client.delete(f"/api/v1/wardrobe/items/{used_top}", headers=auth(u))
    assert r.status_code == 204
    second = (await client.get("/api/v1/outfit/daily", headers=auth(u))).json()
    assert second["cached"] is False
    assert all(o["items"]["top"] != used_top for o in second["outfits"])
    assert t  # silence unused


def test_hex_colors_are_understood():
    assert oe.color_to_name("#1F2A44") == "navy"
    assert oe.color_to_name("#FFFFFF") == "white"
    assert oe.color_to_name("Navy") == "navy"
    assert oe.color_to_name("#zz") is None
    hexy = [fake_item("top", "#F5F5F5"), fake_item("bottom", "#1E2850")]
    assert oe._score_color(hexy) > 15  # navy + white is a harmonious pair

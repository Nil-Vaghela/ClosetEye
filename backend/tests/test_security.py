import io
import uuid
from pathlib import Path

import pytest
from fastapi import HTTPException
from PIL import Image
from sqlalchemy import select, text

from app.core.config import settings
from app.main import app
from app.models.outfit import Outfit
from app.services import quota, storage
from tests.conftest import auth, make_item, make_user


def _jpeg_with_gps() -> bytes:
    img = Image.new("RGB", (64, 64), (200, 30, 30))
    exif = Image.Exif()
    exif[0x8825] = {1: "N", 2: (40.0, 26.0, 46.0)}  # GPSInfo
    exif[0x010F] = "SecretPhoneMaker"
    buf = io.BytesIO()
    img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


def _put_file(rel: str, data: bytes = b"x") -> str:
    p = Path(settings.UPLOAD_DIR) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return storage.stable_url(rel)


# ── Every API route requires auth ────────────────────────────────────────────

PUBLIC = {"/api/v1/auth/phone"}


def _api_routes():
    for r in app.routes:
        path = getattr(r, "path", "")
        if path.startswith("/api/v1") and path not in PUBLIC:
            for m in sorted(getattr(r, "methods", []) - {"HEAD", "OPTIONS"}):
                yield m, path


@pytest.mark.parametrize("method,path", list(_api_routes()))
async def test_every_route_requires_auth(client, method, path):
    url = path.replace("{item_id}", str(uuid.uuid4())).replace("{outfit_id}", str(uuid.uuid4())) \
              .replace("{notification_id}", str(uuid.uuid4()))
    r = await client.request(method, url)
    assert r.status_code in (401, 403), f"{method} {path} -> {r.status_code}"


# ── Signed URLs ──────────────────────────────────────────────────────────────

async def test_uploads_are_private_and_signed(client, db):
    u = await make_user(db)
    url = _put_file(f"garments/{u.id}/original/a.jpg", b"img")
    await make_item(db, u, "top", "white", original_image_url=url)

    assert (await client.get(f"/uploads/garments/{u.id}/original/a.jpg")).status_code in (403, 422)
    items = (await client.get("/api/v1/wardrobe/items", headers=auth(u))).json()
    signed = items[0]["original_image_url"]
    assert "sig=" in signed and "exp=" in signed
    path = signed.replace("http://testserver", "")
    ok = await client.get(path)
    assert ok.status_code == 200 and ok.content == b"img"
    assert (await client.get(path.replace("sig=", "sig=0"))).status_code == 403


async def test_path_traversal_rejected():
    assert storage.local_path("/uploads/../../etc/passwd") is None
    assert storage.rel_path("http://evil.com/x.png") is None


# ── IDOR ─────────────────────────────────────────────────────────────────────

async def test_flatlay_cannot_use_other_users_items(db, monkeypatch):
    from app.services import flatlay_service
    alice, bob = await make_user(db), await make_user(db)
    bobs = await make_item(db, bob, "top", "red")
    monkeypatch.setattr(flatlay_service, "ai_enabled", lambda: True)
    with pytest.raises(RuntimeError, match="No clothing items"):
        await flatlay_service.generate_flatlay(alice.id, item_ids=[str(bobs.id)], db=db)


async def test_tryon_cannot_use_other_users_items(db, tmp_path):
    from app.services import tryon_service
    alice, bob = await make_user(db), await make_user(db)
    alice.body_photo_url = _put_file(f"body_models/{alice.id}/original.jpg")
    await db.commit()
    bobs = await make_item(db, bob, "top", "red")
    with pytest.raises(RuntimeError, match="No clothing items"):
        await tryon_service.generate_try_on_preview(alice.id, [str(bobs.id)], db)


async def test_outfit_create_rejects_foreign_items(client, db):
    alice, bob = await make_user(db), await make_user(db)
    bobs = await make_item(db, bob, "top", "red")
    r = await client.post("/api/v1/outfits/", headers=auth(alice),
                          json={"name": "x", "clothing_item_ids": [str(bobs.id)]})
    assert r.status_code == 422
    r = await client.post("/api/v1/outfits/", headers=auth(alice),
                          json={"name": "x", "clothing_item_ids": [str(uuid.uuid4())]})
    assert r.status_code == 422


async def test_ootd_rejects_foreign_items(client, db):
    alice, bob = await make_user(db), await make_user(db)
    bobs = await make_item(db, bob, "top", "red")
    r = await client.post("/api/v1/ootd", headers=auth(alice),
                          json={"custom_item_ids": [str(bobs.id)], "logged_date": "2026-11-19"})
    assert r.status_code == 422


async def test_batch_add_rejects_foreign_or_external_urls(client, db):
    alice, bob = await make_user(db), await make_user(db)
    bob_url = _put_file(f"garments/{bob.id}/original/b.jpg")
    for bad in (bob_url, "http://169.254.169.254/latest/meta-data", "https://example.com/x.jpg"):
        r = await client.post("/api/v1/wardrobe/batch-add", headers=auth(alice),
                              json={"original_image_url": bad, "items": [{"category": "top"}]})
        assert r.status_code == 422, bad
    own = _put_file(f"garments/{alice.id}/original/a.jpg")
    r = await client.post("/api/v1/wardrobe/batch-add", headers=auth(alice),
                          json={"original_image_url": storage.sign_url(own),
                                "items": [{"category": "top", "product_image_url": bob_url}]})
    assert r.status_code == 201, r.text
    assert r.json()[0]["cleaned_image_url"] is None  # foreign product image dropped


# ── Deleting things ──────────────────────────────────────────────────────────

async def test_delete_item_used_in_outfit(client, db):
    u = await make_user(db)
    t = await make_item(db, u, "top", "white")
    r = await client.post("/api/v1/outfits/", headers=auth(u), json={"name": "solo", "clothing_item_ids": [str(t.id)]})
    assert r.status_code == 201
    await client.post("/api/v1/outfit/wear", headers=auth(u),
                      json={"item_ids": [str(t.id)], "outfit_id": r.json()["id"]})
    r = await client.delete(f"/api/v1/wardrobe/items/{t.id}", headers=auth(u))
    assert r.status_code == 204
    assert (await db.execute(select(Outfit).where(Outfit.owner_id == u.id))).first() is None


async def test_delete_account_removes_everything(client, db):
    u = await make_user(db)
    other = await make_user(db)
    f = _put_file(f"garments/{u.id}/original/a.jpg")
    t = await make_item(db, u, "top", "white", original_image_url=f)
    await make_item(db, u, "bottom", "navy")
    await client.post("/api/v1/outfits/", headers=auth(u), json={"clothing_item_ids": [str(t.id)]})
    await client.post("/api/v1/outfit/wear", headers=auth(u), json={"item_ids": [str(t.id)]})
    await client.post("/api/v1/outfit/feedback", headers=auth(u), json={"item_ids": [str(t.id)], "feedback": "like"})
    await client.get("/api/v1/outfit/daily", headers=auth(u))
    await quota.consume(db, u.id, "llm")
    keep = await make_item(db, other, "top", "red")

    r = await client.delete("/api/v1/users/me", headers=auth(u))
    assert r.status_code == 204
    for table, col in [("users", "id"), ("clothing_items", "owner_id"), ("outfits", "owner_id"),
                       ("ootd_logs", "user_id"), ("outfit_history", "user_id"), ("daily_outfits", "user_id"),
                       ("outfit_feedback", "user_id"), ("ai_usage", "user_id")]:
        n = (await db.execute(text(f"SELECT count(*) FROM {table} WHERE {col} = :u"), {"u": u.id})).scalar_one()
        assert n == 0, table
    assert not (Path(settings.UPLOAD_DIR) / "garments" / str(u.id)).exists()
    assert (await client.get("/api/v1/users/me", headers=auth(u))).status_code == 401
    assert (await client.get("/api/v1/wardrobe/items", headers=auth(other))).json()[0]["id"] == str(keep.id)


# ── Upload validation ────────────────────────────────────────────────────────

def test_upload_cleaning_strips_gps_and_rejects_non_images():
    from app.services.image_upload import clean_image_bytes
    out = clean_image_bytes(_jpeg_with_gps())
    img = Image.open(io.BytesIO(out))
    assert not img.getexif()
    with pytest.raises(HTTPException) as e:
        clean_image_bytes(b"<?php evil ?>")
    assert e.value.status_code == 415


async def test_shopping_upload_accepts_octet_stream(client, db, monkeypatch):
    from app.api.routes import shopping
    monkeypatch.setattr(shopping, "extract_garment", lambda b, t: b)
    monkeypatch.setattr(shopping, "dewrinkle_and_clean", lambda b: b)

    async def _attrs(_):
        raise RuntimeError("no ai in tests")
    monkeypatch.setattr(shopping.ai_service, "detect_attributes", _attrs)
    u = await make_user(db)
    r = await client.post("/api/v1/shopping/items", headers=auth(u),
                          files={"image": ("x.bin", _jpeg_with_gps(), "application/octet-stream")},
                          data={"category": "top"})
    assert r.status_code == 201, r.text


# ── Cost controls ────────────────────────────────────────────────────────────

async def test_quota_and_budget(db, monkeypatch):
    u = await make_user(db)
    for _ in range(settings.QUOTA_TRYON_PER_DAY):
        await quota.consume(db, u.id, "tryon")
    with pytest.raises(HTTPException) as e:
        await quota.consume(db, u.id, "tryon")
    assert e.value.status_code == 429 and "try ons" in e.value.detail

    monkeypatch.setattr(settings, "DAILY_AI_BUDGET_USD", 0.0)
    v = await make_user(db)
    with pytest.raises(HTTPException) as e:
        await quota.consume(db, v.id, "llm")
    assert e.value.status_code == 503


async def test_llm_analysis_is_cached(client, db, monkeypatch):
    from app.api.routes import wardrobe
    calls = []

    async def fake(items):
        calls.append(1)
        return {"style": "minimal"}
    monkeypatch.setattr(wardrobe.ai_service, "analyze_style_dna", fake)
    u = await make_user(db)
    await make_item(db, u, "top", "white")
    for _ in range(3):
        r = await client.get("/api/v1/wardrobe/style-dna", headers=auth(u))
        assert r.json() == {"style": "minimal"}
    assert len(calls) == 1


# ── Misc ─────────────────────────────────────────────────────────────────────

async def test_error_format_and_legal_pages(client, db):
    u = await make_user(db)
    r = await client.get(f"/api/v1/wardrobe/items/{uuid.uuid4()}", headers=auth(u))
    assert r.status_code == 404 and r.json()["error"]["message"] == r.json()["detail"]
    for p in ("/legal/privacy", "/legal/terms", "/legal/delete-account", "/support"):
        page = await client.get(p)
        assert page.status_code == 200 and "Drape" in page.text and "—" not in page.text


def test_prod_refuses_unsafe_config():
    from app.core.config import Settings
    with pytest.raises(Exception):
        Settings(_env_file=None, ENV="prod", SECRET_KEY="change-me-in-production", BASE_URL="https://api.x")
    Settings(_env_file=None, ENV="prod", DEBUG=False, SECRET_KEY="k" * 40, BASE_URL="https://api.x")


async def test_gemini_adapter_maps_openai_calls(monkeypatch):
    """The Gemini adapter turns OpenAI-style chat/image calls into Vertex requests."""
    import base64
    import io as _io
    from types import SimpleNamespace as NS
    from app.services import ai_client

    seen = {}

    class FakeModels:
        async def generate_content(self, model, contents, config):
            seen.setdefault("calls", []).append((model, contents, config))
            if config.response_modalities:
                buf = _io.BytesIO(); Image.new("RGB", (4, 4)).save(buf, format="JPEG")
                part = NS(inline_data=NS(data=buf.getvalue()))
                return NS(candidates=[NS(content=NS(parts=[part]))])
            return NS(text='{"category":"top"}')

    compat = ai_client.GeminiCompat.__new__(ai_client.GeminiCompat)
    compat._genai = NS(aio=NS(models=FakeModels()))
    compat.chat = ai_client._Chat(compat)
    compat.images = ai_client._Images(compat)

    png = _io.BytesIO(); Image.new("RGB", (4, 4)).save(png, format="PNG")
    data_url = "data:image/png;base64," + base64.b64encode(png.getvalue()).decode()
    r = await compat.chat.completions.create(model="gpt-4o-mini", max_tokens=50, messages=[
        {"role": "system", "content": "be terse"},
        {"role": "user", "content": [{"type": "image_url", "image_url": {"url": data_url}},
                                     {"type": "text", "text": "what is it"}]},
    ])
    assert r.choices[0].message.content == '{"category":"top"}'
    model, contents, cfg = seen["calls"][0]
    assert model == settings.VERTEX_TEXT_MODEL and cfg.system_instruction == "be terse"
    assert len(contents[0].parts) == 2 and cfg.max_output_tokens >= 2048

    f = _io.BytesIO(png.getvalue()); f.name = "a.png"
    out = await compat.images.edit(model="gpt-image-1", image=[f, f], prompt="dress them")
    img = base64.b64decode(out.data[0].b64_json)
    assert img[:8] == b"\x89PNG\r\n\x1a\n"  # always PNG back
    assert seen["calls"][1][0] == settings.VERTEX_IMAGE_MODEL and len(seen["calls"][1][1][0].parts) == 3

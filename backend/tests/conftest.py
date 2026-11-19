"""Test harness: real Postgres (TEST_DATABASE_URL), migrations applied once, tables truncated per test."""
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

TEST_DB = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+asyncpg://drape:drape@127.0.0.1:55432/drape_test"
)
os.environ["DATABASE_URL"] = TEST_DB
os.environ["ENV"] = "test"
os.environ["SECRET_KEY"] = "test-secret-key-that-is-long-enough-123456"
os.environ["BASE_URL"] = "http://testserver"
os.environ.setdefault("UPLOAD_DIR", str(Path(__file__).parent / ".uploads"))
os.environ["OPENAI_API_KEY"] = ""

BACKEND = Path(__file__).resolve().parents[1]

import httpx  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.core.database import async_session  # noqa: E402
from app.core.security import create_access_token  # noqa: E402
from app.main import app  # noqa: E402
from app.models.clothing import ClothingItem  # noqa: E402
from app.models.user import User  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _migrate():
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND, check=True, env={**os.environ}, capture_output=True,
    )


@pytest.fixture(autouse=True)
async def _clean():
    yield
    async with async_session() as s:
        rows = await s.execute(text(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> 'alembic_version'"
        ))
        names = ", ".join(f'"{r[0]}"' for r in rows)
        if names:
            await s.execute(text(f"TRUNCATE {names} CASCADE"))
        await s.commit()


@pytest.fixture
async def db():
    async with async_session() as s:
        yield s


async def make_user(db, phone: str | None = None) -> User:
    u = User(phone_number=phone or f"+1555{uuid.uuid4().int % 10**7:07d}", firebase_uid=uuid.uuid4().hex)
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


async def make_item(db, owner: User, category: str, color: str | None = None, tags=None, **kw) -> ClothingItem:
    item = ClothingItem(
        owner_id=owner.id,
        name=kw.pop("name", f"{color or ''} {category}".strip()),
        category=category,
        color_primary=color,
        tags=tags or [],
        original_image_url=kw.pop("original_image_url", f"http://testserver/uploads/garments/{owner.id}/original/{uuid.uuid4()}.jpg"),
        **kw,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


def auth(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(str(user.id))}"}


@pytest.fixture
async def client():
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as c:
        yield c

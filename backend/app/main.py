from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes import auth, wardrobe, outfits, suggestions, tryon, users, shopping, ootd
from app.core.config import settings
from app.core.database import engine, Base

# Import all models so Base.metadata is populated before create_all
import app.models  # noqa: F401

app = FastAPI(
    title="Drape API",
    description="AI-powered digital wardrobe — upload clothes, get outfit suggestions, virtual try-on",
    version="0.3.0",
)

# Serve uploaded files (body photos, silhouettes, garment images)
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOAD_DIR)), name="uploads")

# CORS — allow mobile app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def _create_missing_tables():
    """Auto-create any tables that don't exist yet (safe — won't drop/alter existing)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


@app.get("/health")
async def health_check():
    return {"status": "ok", "version": "0.3.0"}


# ── Routes ──────────────────────────────────────────────────
app.include_router(auth.router,        prefix="/api/v1/auth",        tags=["Auth"])
app.include_router(users.router,       prefix="/api/v1/users",       tags=["Users"])
app.include_router(wardrobe.router,    prefix="/api/v1/wardrobe",    tags=["Wardrobe"])
app.include_router(outfits.router,     prefix="/api/v1/outfits",     tags=["Outfits"])
app.include_router(suggestions.router, prefix="/api/v1/suggestions", tags=["Suggestions"])
app.include_router(tryon.router,       prefix="/api/v1/tryon",       tags=["Virtual Try-On"])
app.include_router(shopping.router,    prefix="/api/v1/shopping",    tags=["Shopping"])
app.include_router(ootd.router,        prefix="/api/v1/ootd",        tags=["OOTD"])

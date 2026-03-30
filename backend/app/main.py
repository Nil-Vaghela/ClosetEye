from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, wardrobe, outfits, suggestions, tryon
from app.core.config import settings

app = FastAPI(
    title="ClosetEye API",
    description="Digital wardrobe assistant — upload clothes, get outfit suggestions, and virtual try-on",
    version="0.1.0",
)

# CORS — allow mobile app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health_check():
    return {"status": "ok", "version": "0.1.0"}


# ── Routes ──────────────────────────────────────────────────
app.include_router(auth.router,        prefix="/api/v1/auth",        tags=["Auth"])
app.include_router(wardrobe.router,    prefix="/api/v1/wardrobe",    tags=["Wardrobe"])
app.include_router(outfits.router,     prefix="/api/v1/outfits",     tags=["Outfits"])
app.include_router(suggestions.router, prefix="/api/v1/suggestions", tags=["Suggestions"])
app.include_router(tryon.router,       prefix="/api/v1/tryon",       tags=["Virtual Try-On"])

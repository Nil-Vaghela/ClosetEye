import logging

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import (
    auth, files, legal, ootd, outfit_engine, outfits, shopping, suggestions, tryon, users, wardrobe,
)
from app.core.config import settings
from app.core.database import Base, engine

# Import all models so Base.metadata is populated
import app.models  # noqa: F401

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("drape")

app = FastAPI(
    title="Drape API",
    description="AI-powered digital wardrobe",
    version="1.0.0",
    docs_url=None if settings.is_prod else "/docs",
    redoc_url=None,
    openapi_url=None if settings.is_prod else "/openapi.json",
)

if settings.ALLOWED_ORIGINS:  # only the website needs CORS; mobile apps don't
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-UTC-Offset"],
    )


# ── Consistent error format: {"detail": msg, "error": {"code", "message"}} ──────
def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": message, "error": {"code": code, "message": message}})


@app.exception_handler(HTTPException)
async def _http_error(_: Request, exc: HTTPException):
    msg = exc.detail if isinstance(exc.detail, str) else "Request failed"
    return _error(exc.status_code, f"http_{exc.status_code}", msg)


@app.exception_handler(RequestValidationError)
async def _validation_error(_: Request, exc: RequestValidationError):
    first = exc.errors()[0] if exc.errors() else {}
    field = ".".join(str(p) for p in first.get("loc", [])[1:]) or "request"
    return _error(422, "validation_error", f"Please check {field}: {first.get('msg', 'invalid value')}")


@app.exception_handler(Exception)
async def _unhandled(_: Request, exc: Exception):
    logger.exception("Unhandled error")
    return _error(500, "server_error", "Something went wrong on our side. Please try again.")


@app.on_event("startup")
async def _dev_create_tables():
    """Dev convenience only. Staging/prod schemas come from Alembic migrations."""
    if settings.ENV == "dev":
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)


@app.get("/health")
async def health_check():
    return {"status": "ok", "version": "1.0.0"}


# ── Routes ──────────────────────────────────────────────────
app.include_router(files.router, tags=["Files"])
app.include_router(legal.router, tags=["Legal"])
app.include_router(auth.router,          prefix="/api/v1/auth",        tags=["Auth"])
app.include_router(users.router,         prefix="/api/v1/users",       tags=["Users"])
app.include_router(wardrobe.router,      prefix="/api/v1/wardrobe",    tags=["Wardrobe"])
app.include_router(outfits.router,       prefix="/api/v1/outfits",     tags=["Outfits"])
app.include_router(suggestions.router,   prefix="/api/v1/suggestions", tags=["Suggestions"])
app.include_router(tryon.router,         prefix="/api/v1/tryon",       tags=["Virtual Try-On"])
app.include_router(shopping.router,      prefix="/api/v1/shopping",    tags=["Shopping"])
app.include_router(ootd.router,          prefix="/api/v1/ootd",        tags=["OOTD"])
app.include_router(outfit_engine.router, prefix="/api/v1/outfit",      tags=["Outfit Engine"])

"""
Users router — DR-S2
====================
Handles body model creation and retrieval for the authenticated user.

Endpoints:
  GET  /api/v1/users/me             — current user profile (incl. body model state)
  POST /api/v1/users/me/body-model  — upload photo + measurements → generate silhouette
  GET  /api/v1/users/me/body-model  — fetch body model status + URLs
"""
from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.user import BodyModelResponse, UserResponse
from app.services.body_model_service import generate_silhouette, save_upload
from app.services.image_upload import clean_image_bytes
from app.services.storage import stable_url
from app.services.account_service import delete_account
from app.services.avatar_service import generate_avatar
from app.services import quota
from fastapi.concurrency import run_in_threadpool
import logging

logger = logging.getLogger(__name__)

router = APIRouter()

# Where uploads live inside the container (mounted volume in Docker)
UPLOAD_DIR = Path("uploads")


# ── GET /users/me ─────────────────────────────────────────────────────────────

@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """Return the authenticated user's full profile including body model state."""
    return UserResponse.model_validate(current_user)


# ── POST /users/me/body-model ─────────────────────────────────────────────────

@router.post(
    "/me/body-model",
    response_model=BodyModelResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_body_model(
    # Photo sent as multipart form
    photo: UploadFile = File(..., description="Front-facing full-body photo"),
    # Measurements sent alongside the photo in the same multipart form
    height_cm: int = Form(..., ge=100, le=250),
    weight_kg: int = Form(..., ge=30, le=300),
    body_type: str = Form(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Upload a front-facing reference photo + body measurements.
    Runs rembg background removal to generate a clean body silhouette.
    Stores both the original photo and the silhouette, then marks
    body_model_ready = True on the user record.
    """
    # ── 1. Read photo bytes ───────────────────────────────────────────────────
    image_bytes = await photo.read()
    if len(image_bytes) > 20 * 1024 * 1024:  # 20 MB cap
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Photo must be under 20 MB.",
        )

    image_bytes = clean_image_bytes(image_bytes)  # real type check + strips GPS/EXIF
    detected_mime = "image/jpeg"

    # ── 2. Validate body_type ─────────────────────────────────────────────────
    valid_body_types = {"slim", "regular", "athletic", "curvy", "plus"}
    if body_type not in valid_body_types:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"body_type must be one of: {sorted(valid_body_types)}",
        )

    # ── 3. Save original photo ────────────────────────────────────────────────
    user_dir = UPLOAD_DIR / "body_models" / str(current_user.id)
    ext = "jpg" if detected_mime == "image/jpeg" else "png"
    original_filename = f"original.{ext}"
    original_path = user_dir / original_filename
    save_upload(image_bytes, original_path)

    # ── 5. Personal avatar (digital twin) for try-on; falls back to a silhouette ─
    await quota.consume(db, current_user.id, "avatar")
    avatar_bytes = await generate_avatar(image_bytes, height_cm, weight_kg, body_type)
    avatar_url = None
    if avatar_bytes:
        save_upload(avatar_bytes, user_dir / "avatar.png")
        avatar_url = stable_url(f"body_models/{current_user.id}/avatar.png")

    try:
        silhouette_bytes = await run_in_threadpool(generate_silhouette, image_bytes)
    except RuntimeError:
        logger.exception("Silhouette generation failed")
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="We couldn't find you in that photo. Try a well-lit, full-body photo facing the camera.",
        )

    # ── 6. Save silhouette ────────────────────────────────────────────────────
    silhouette_path = user_dir / "silhouette.png"
    save_upload(silhouette_bytes, silhouette_path)

    # ── 7. Build public URLs ──────────────────────────────────────────────────
    # Private: only reachable through signed URLs (see services/storage.py)
    body_photo_url = stable_url(f"body_models/{current_user.id}/{original_filename}")
    body_silhouette_url = stable_url(f"body_models/{current_user.id}/silhouette.png")

    # ── 8. Persist to DB ──────────────────────────────────────────────────────
    current_user.body_photo_url = body_photo_url
    current_user.body_silhouette_url = avatar_url or body_silhouette_url
    current_user.avatar_url = avatar_url
    current_user.height_cm = height_cm
    current_user.weight_kg = weight_kg
    current_user.body_type = body_type
    current_user.body_model_ready = True

    await db.commit()
    await db.refresh(current_user)

    return BodyModelResponse.model_validate(current_user)


# ── GET /users/me/body-model ──────────────────────────────────────────────────

@router.get("/me/body-model", response_model=BodyModelResponse)
async def get_body_model(current_user: User = Depends(get_current_user)):
    """Return the current user's body model status and URLs."""
    if not current_user.body_model_ready:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Body model not yet created. POST to /users/me/body-model first.",
        )
    return BodyModelResponse.model_validate(current_user)


# ── DELETE /users/me ──────────────────────────────────────────────────────────

@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete the account: every DB row, every stored photo, and the Firebase login."""
    await delete_account(db, current_user)


@router.delete("/me/body-model", status_code=status.HTTP_204_NO_CONTENT)
async def delete_body_model(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete the body photo + silhouette any time."""
    from app.services import storage
    for url in (current_user.body_photo_url, current_user.body_silhouette_url, current_user.avatar_url):
        storage.delete(url)
    current_user.body_photo_url = None
    current_user.body_silhouette_url = None
    current_user.avatar_url = None
    current_user.body_model_ready = False
    await db.commit()

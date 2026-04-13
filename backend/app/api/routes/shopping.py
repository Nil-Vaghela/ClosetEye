"""
Shopping Items Router
=====================
Handle temporary "shopping" items (from external links).
Auto-expire after 30 days.
"""
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone

from app.core.database import get_db
from app.core.config import settings
from app.api.deps import get_current_user
from app.models.user import User
from app.models.shopping import ShoppingItem
from app.models.clothing import ClothingCategory
from app.schemas.shopping import ShoppingItemResponse
from app.services.file_service import file_service
from app.services.garment_service import extract_garment, dewrinkle_and_clean, detect_photo_type_heuristic
from app.services.ai_service import ai_service

logger = logging.getLogger(__name__)
router = APIRouter()



@router.post("/items", response_model=ShoppingItemResponse, status_code=201)
async def upload_shopping_item(
    image: UploadFile = File(...),
    category: ClothingCategory | None = Form(None),
    name: str | None = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Upload a shopping item (from a link or external source).
    Uses the same pipeline as wardrobe items but expires after 30 days.

    Form parameters:
    - image: image file (JPEG, PNG, WEBP, HEIC)
    - category: optional override for detected category
    - name: optional item name
    """
    # ── 1. Validate file type and size ──────────────────────────────────────────
    allowed_types = {"image/jpeg", "image/png", "image/webp", "image/heic"}
    if image.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type. Use JPEG, PNG, WEBP, or HEIC.",
        )

    image_bytes = await image.read()
    max_bytes = settings.MAX_FILE_SIZE_MB * 1024 * 1024
    if len(image_bytes) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image must be under {settings.MAX_FILE_SIZE_MB} MB.",
        )

    try:
        # ── 2. Save original image ─────────────────────────────────────────────
        logger.info(f"Saving original shopping item for user {current_user.id}")
        _, original_url = await file_service.save(
            image_bytes,
            f"shopping/{current_user.id}/original",
            "jpg",
        )

        # ── 3. Extract garment ─────────────────────────────────────────────────
        logger.info("Extracting garment")
        photo_type = detect_photo_type_heuristic(image_bytes)
        garment_bytes = extract_garment(image_bytes, photo_type)

        # ── 4. Dewrinkle and clean ────────────────────────────────────────────
        logger.info("Cleaning image")
        cleaned_bytes = dewrinkle_and_clean(garment_bytes)

        # ── 5. Save cleaned image ──────────────────────────────────────────────
        logger.info("Saving cleaned image")
        _, cleaned_url = await file_service.save(
            cleaned_bytes,
            f"shopping/{current_user.id}/cleaned",
            "png",
        )

        # ── 6. AI attribute detection ──────────────────────────────────────────
        logger.info("Running AI attribute detection")
        try:
            attributes = await ai_service.detect_attributes(cleaned_bytes)
        except Exception as exc:
            logger.warning(f"AI attribute detection failed: {exc}; using defaults")
            attributes = {
                "name": name,
                "category": category or "other",
                "color_primary": None,
                "color_secondary": None,
            }

        # ── 7. Map to enum with fallback ───────────────────────────────────────
        detected_category = category or attributes.get("category", "other")
        try:
            detected_category = ClothingCategory(detected_category)
        except ValueError:
            detected_category = ClothingCategory.OTHER

        # ── 8. Persist to database ────────────────────────────────────────────
        logger.info("Creating ShoppingItem in database")
        item = ShoppingItem(
            owner_id=current_user.id,
            name=name or attributes.get("name"),
            category=detected_category,
            color_primary=attributes.get("color_primary"),
            original_image_url=original_url,
            cleaned_image_url=cleaned_url,
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)

        logger.info(f"Shopping item created: {item.id}")
        return item

    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"Shopping item upload failed: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Upload processing failed: {str(exc)}",
        ) from exc


@router.get("/items", response_model=list[ShoppingItemResponse])
async def list_shopping_items(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all non-expired shopping items for the user."""
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(ShoppingItem).where(
            ShoppingItem.owner_id == current_user.id,
            ShoppingItem.expires_at > now,
        ).order_by(ShoppingItem.created_at.desc())
    )
    return result.scalars().all()


@router.delete("/items/{item_id}", status_code=204)
async def delete_shopping_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a shopping item."""
    result = await db.execute(
        select(ShoppingItem).where(
            ShoppingItem.id == item_id,
            ShoppingItem.owner_id == current_user.id,
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Shopping item not found")

    # Clean up files
    try:
        if item.original_image_url:
            await file_service.delete(item.original_image_url)
        if item.cleaned_image_url:
            await file_service.delete(item.cleaned_image_url)
    except Exception as exc:
        logger.warning(f"Failed to clean up files: {exc}")

    await db.delete(item)
    await db.commit()

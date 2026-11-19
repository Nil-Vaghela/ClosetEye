import json
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.file_service import file_service
from app.services.tryon_service import generate_try_on_preview
from app.services.flatlay_service import generate_flatlay
from app.services import quota
from app.services.storage import sign_url

logger = logging.getLogger(__name__)
router = APIRouter()


class TryOnPreviewRequest(BaseModel):
    """Request body for try-on preview generation."""
    item_ids: list[UUID] = Field(..., max_length=6)
    shopping_item_ids: list[UUID] | None = None


class TryOnPreviewResponse(BaseModel):
    """Response with generated try-on preview URL."""
    preview_url: str


@router.post("/preview", response_model=TryOnPreviewResponse)
async def generate_try_on(
    request: TryOnPreviewRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Generate a virtual try-on preview.

    Pipeline:
    1. Validate user has body model ready
    2. Fetch body silhouette from user's body model
    3. Fetch cleaned garment images for each item
    4. Composite them together (MVP: simple layering)
    5. Save preview image
    6. Return public URL

    Request body:
    {
        "item_ids": ["uuid1", "uuid2", ...],
        "shopping_item_ids": ["uuid1", ...] (optional)
    }
    """
    # ── Validate user has body model ───────────────────────────────────────────
    # With DALL-E 3, we only need body_model_ready (body_photo_url is enough).
    # The PIL fallback additionally requires body_silhouette_url, but that is
    # handled gracefully inside generate_try_on_preview().
    if not current_user.body_model_ready:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Body model not ready. Please upload a body photo first.",
        )

    # ── Validate item IDs ──────────────────────────────────────────────────────
    if not request.item_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one item ID is required.",
        )

    await quota.consume(db, current_user.id, "tryon")
    try:
        # ── Generate try-on preview ────────────────────────────────────────────
        logger.info(f"Generating try-on for {len(request.item_ids)} items")
        preview_bytes = await generate_try_on_preview(
            user_id=current_user.id,
            item_ids=[str(id_) for id_ in request.item_ids],
            db=db,
            shopping_item_ids=[str(id_) for id_ in (request.shopping_item_ids or [])],
        )

        # ── Save preview image ─────────────────────────────────────────────────
        logger.info("Saving try-on preview")
        _, preview_url = await file_service.save(
            preview_bytes,
            f"tryon/{current_user.id}/previews",
            "png",
        )

        return TryOnPreviewResponse(preview_url=sign_url(preview_url))

    except HTTPException:
        raise
    except (RuntimeError, FileNotFoundError) as exc:
        logger.warning("Try-on could not run: %s", exc)
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Try-on generation failed")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Try on is having a moment. Please try again soon.",
        ) from exc


# ─────────────────────────────────────────────────────────────────────────────
# Outfit Flatlay endpoint
# ─────────────────────────────────────────────────────────────────────────────

class FlatLayRequest(BaseModel):
    """Request body for outfit flatlay generation."""
    item_ids: list[UUID] = Field(..., max_length=8)


class FlatLayResponse(BaseModel):
    """Response with generated flatlay image URL."""
    flatlay_url: str


@router.post("/flatlay", response_model=FlatLayResponse)
async def generate_outfit_flatlay(
    request: FlatLayRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Generate a product-style outfit flatlay for selected wardrobe items.

    No model, no body — just a clean fashion editorial board showing
    the exact garments arranged as a coordinated look.

    Powered by gpt-image-1 with strict fidelity constraints.
    """
    if not request.item_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="At least one item ID is required.",
        )

    await quota.consume(db, current_user.id, "flatlay")
    try:
        logger.info(f"Generating flatlay for {len(request.item_ids)} items")
        flatlay_bytes = await generate_flatlay(
            current_user.id,
            item_ids=[str(id_) for id_ in request.item_ids],
            db=db,
        )

        _, flatlay_url = await file_service.save(
            flatlay_bytes,
            f"flatlay/{current_user.id}",
            "png",
        )

        return FlatLayResponse(flatlay_url=sign_url(flatlay_url))

    except HTTPException:
        raise
    except (RuntimeError, FileNotFoundError) as exc:
        logger.warning("Flatlay could not run: %s", exc)
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Flatlay generation failed")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Couldn't build your outfit board right now. Please try again soon.",
        ) from exc

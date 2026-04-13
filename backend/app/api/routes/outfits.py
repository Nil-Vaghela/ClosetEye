from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.outfit import Outfit, OutfitItem
from app.schemas.outfit import OutfitCreate, OutfitResponse

router = APIRouter()


def _to_response(outfit: Outfit) -> OutfitResponse:
    """Convert ORM Outfit to OutfitResponse, populating clothing_item_ids."""
    item_ids = [oi.clothing_item_id for oi in sorted(outfit.items, key=lambda x: x.layer_order)]
    return OutfitResponse(
        id=outfit.id,
        name=outfit.name,
        occasion=outfit.occasion,
        match_score=outfit.match_score,
        is_ai_suggested=outfit.is_ai_suggested,
        preview_image_url=outfit.preview_image_url,
        created_at=outfit.created_at,
        clothing_item_ids=item_ids,
    )


@router.post("/", response_model=OutfitResponse, status_code=201)
async def create_outfit(
    payload: OutfitCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Save a new outfit combination."""
    outfit = Outfit(
        owner_id=current_user.id,
        name=payload.name,
        occasion=payload.occasion,
        preview_image_url=getattr(payload, "preview_image_url", None),
    )
    db.add(outfit)
    await db.flush()

    for idx, item_id in enumerate(payload.clothing_item_ids):
        db.add(OutfitItem(outfit_id=outfit.id, clothing_item_id=item_id, layer_order=idx))

    await db.commit()

    # Re-fetch with items eagerly loaded
    result = await db.execute(
        select(Outfit)
        .where(Outfit.id == outfit.id)
        .options(selectinload(Outfit.items))
    )
    outfit = result.scalar_one()
    return _to_response(outfit)


@router.get("/", response_model=list[OutfitResponse])
async def list_outfits(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all saved outfits for the current user."""
    result = await db.execute(
        select(Outfit)
        .where(Outfit.owner_id == current_user.id)
        .options(selectinload(Outfit.items))
        .order_by(Outfit.created_at.desc())
    )
    outfits = result.scalars().all()
    return [_to_response(o) for o in outfits]


@router.delete("/{outfit_id}", status_code=204)
async def delete_outfit(
    outfit_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Outfit).where(Outfit.id == outfit_id, Outfit.owner_id == current_user.id)
    )
    outfit = result.scalar_one_or_none()
    if not outfit:
        raise HTTPException(status_code=404, detail="Outfit not found")
    await db.delete(outfit)
    await db.commit()

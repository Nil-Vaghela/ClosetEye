from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.outfit import Outfit, OutfitItem
from app.schemas.outfit import OutfitCreate, OutfitResponse

router = APIRouter()


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
    )
    db.add(outfit)
    await db.flush()  # get outfit.id

    for idx, item_id in enumerate(payload.clothing_item_ids):
        db.add(OutfitItem(outfit_id=outfit.id, clothing_item_id=item_id, layer_order=idx))

    await db.commit()
    await db.refresh(outfit)

    return OutfitResponse(
        id=outfit.id,
        name=outfit.name,
        occasion=outfit.occasion,
        match_score=outfit.match_score,
        is_ai_suggested=outfit.is_ai_suggested,
        preview_image_url=outfit.preview_image_url,
        created_at=outfit.created_at,
        clothing_item_ids=payload.clothing_item_ids,
    )


@router.get("/", response_model=list[OutfitResponse])
async def list_outfits(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Outfit).where(Outfit.owner_id == current_user.id).order_by(Outfit.created_at.desc())
    )
    return result.scalars().all()


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

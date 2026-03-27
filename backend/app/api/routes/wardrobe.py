from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.clothing import ClothingItem, ClothingCategory
from app.schemas.clothing import ClothingItemResponse, ClothingItemUpdate

router = APIRouter()


@router.post("/items", response_model=ClothingItemResponse, status_code=201)
async def upload_clothing_item(
    image: UploadFile = File(...),
    category: ClothingCategory = Form(...),
    name: str | None = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Upload a photo of a clothing item.
    The backend will:
    1. Save the original image
    2. Extract the clothing from the background (AI)
    3. Detect color, category auto-correction, etc.
    4. Store the cleaned version
    """
    # TODO: save file to storage (local / S3)
    # TODO: call AI service to extract clothing, detect color, dewrinkle
    original_url = f"/uploads/{current_user.id}/{image.filename}"

    item = ClothingItem(
        owner_id=current_user.id,
        name=name,
        category=category,
        original_image_url=original_url,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.get("/items", response_model=list[ClothingItemResponse])
async def list_clothing_items(
    category: ClothingCategory | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all items in the user's wardrobe, optionally filtered by category."""
    query = select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    if category:
        query = query.where(ClothingItem.category == category)
    result = await db.execute(query.order_by(ClothingItem.created_at.desc()))
    return result.scalars().all()


@router.get("/items/{item_id}", response_model=ClothingItemResponse)
async def get_clothing_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@router.patch("/items/{item_id}", response_model=ClothingItemResponse)
async def update_clothing_item(
    item_id: UUID,
    payload: ClothingItemUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    await db.commit()
    await db.refresh(item)
    return item


@router.delete("/items/{item_id}", status_code=204)
async def delete_clothing_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    await db.delete(item)
    await db.commit()

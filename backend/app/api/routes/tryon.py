from fastapi import APIRouter, Depends, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.outfit import TryOnRequest, TryOnResponse

router = APIRouter()


@router.post("/", response_model=TryOnResponse)
async def virtual_try_on(
    body_photo: UploadFile = File(...),
    clothing_item_ids: str = Form(...),  # comma-separated UUIDs
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Virtual try-on: overlay selected clothing items onto the user's body photo.

    Pipeline:
    1. Receive user body photo
    2. Fetch cleaned clothing images for each item
    3. Call AI try-on service (pose estimation → garment warp → composite)
    4. Return the generated preview image
    """
    # TODO: implement AI virtual try-on pipeline
    return TryOnResponse(preview_image_url="/placeholder/tryon-result.png", processing_time_ms=0)

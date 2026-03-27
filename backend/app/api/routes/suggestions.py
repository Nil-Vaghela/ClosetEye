from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.outfit import SuggestionRequest, SuggestionResponse

router = APIRouter()


@router.post("/", response_model=SuggestionResponse)
async def get_outfit_suggestions(
    payload: SuggestionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    AI-powered outfit suggestions based on the user's wardrobe.

    This endpoint will:
    1. Fetch all the user's clothing items
    2. Use AI to score mix-match compatibility
    3. Return top outfit combos + shopping recommendations
       (e.g. "A white sneaker would complete 4 more outfits")
    """
    # TODO: implement AI suggestion service
    return SuggestionResponse(outfits=[], shopping_suggestions=[])

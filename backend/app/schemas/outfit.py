from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class OutfitCreate(BaseModel):
    name: str | None = None
    occasion: str | None = None
    clothing_item_ids: list[UUID]


class OutfitResponse(BaseModel):
    id: UUID
    name: str | None
    occasion: str | None
    match_score: float | None
    is_ai_suggested: bool
    preview_image_url: str | None
    created_at: datetime
    clothing_item_ids: list[UUID] = []

    model_config = {"from_attributes": True}


class SuggestionRequest(BaseModel):
    occasion: str | None = None  # e.g. "work", "casual", "date night"
    season: str | None = None
    exclude_item_ids: list[UUID] = []  # items to exclude


class SuggestionResponse(BaseModel):
    outfits: list[OutfitResponse]
    shopping_suggestions: list[str] = []  # e.g. "A navy blazer would pair well with 5 of your items"


class TryOnRequest(BaseModel):
    clothing_item_ids: list[UUID]  # items to virtually try on
    # user body photo is sent as file upload


class TryOnResponse(BaseModel):
    preview_image_url: str  # generated try-on image
    processing_time_ms: int

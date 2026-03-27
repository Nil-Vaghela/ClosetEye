from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

from app.models.clothing import ClothingCategory, Season


class ClothingItemCreate(BaseModel):
    name: str | None = None
    category: ClothingCategory
    color_primary: str | None = None
    color_secondary: str | None = None
    brand: str | None = None
    season: Season = Season.ALL
    tags: list[str] = []


class ClothingItemResponse(BaseModel):
    id: UUID
    name: str | None
    category: ClothingCategory
    color_primary: str | None
    color_secondary: str | None
    brand: str | None
    season: Season
    tags: list[str]
    original_image_url: str
    cleaned_image_url: str | None
    style_score: float | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ClothingItemUpdate(BaseModel):
    name: str | None = None
    category: ClothingCategory | None = None
    color_primary: str | None = None
    color_secondary: str | None = None
    brand: str | None = None
    season: Season | None = None
    tags: list[str] | None = None

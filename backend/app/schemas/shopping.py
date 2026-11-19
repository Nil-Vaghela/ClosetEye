from pydantic import field_serializer
from app.services.storage import sign_url
"""Shopping item schemas."""
from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

from app.models.clothing import ClothingCategory


class ShoppingItemCreate(BaseModel):
    category: ClothingCategory
    name: str | None = None
    color_primary: str | None = None


class ShoppingItemResponse(BaseModel):
    id: UUID
    name: str | None
    category: ClothingCategory
    color_primary: str | None
    original_image_url: str
    cleaned_image_url: str | None
    expires_at: datetime
    created_at: datetime

    model_config = {"from_attributes": True}

    @field_serializer("original_image_url", "cleaned_image_url")
    def _sign(self, v):
        return sign_url(v)



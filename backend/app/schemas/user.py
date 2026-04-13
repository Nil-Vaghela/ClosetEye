from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime
from typing import Literal


BodyType = Literal["slim", "regular", "athletic", "curvy", "plus"]


class UserResponse(BaseModel):
    id: UUID
    phone_number: str
    full_name: str | None
    avatar_url: str | None
    # Body model fields
    body_photo_url: str | None = None
    body_silhouette_url: str | None = None
    height_cm: int | None = None
    weight_kg: int | None = None
    body_type: str | None = None
    body_model_ready: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    is_new_user: bool = False   # True on first sign-in — mobile shows profile setup screen
    user: UserResponse


class BodyModelRequest(BaseModel):
    height_cm: int = Field(..., ge=100, le=250, description="Height in centimetres")
    weight_kg: int = Field(..., ge=30, le=300, description="Weight in kilograms")
    body_type: BodyType = Field(..., description="Body shape category")


class BodyModelResponse(BaseModel):
    body_photo_url: str
    body_silhouette_url: str
    height_cm: int
    weight_kg: int
    body_type: str
    body_model_ready: bool

    model_config = {"from_attributes": True}

from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class UserResponse(BaseModel):
    id: UUID
    phone_number: str
    full_name: str | None
    avatar_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    is_new_user: bool = False   # True on first sign-in — mobile shows profile setup screen
    user: UserResponse

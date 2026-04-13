"""OOTD log schemas."""
from pydantic import BaseModel
from uuid import UUID
from datetime import datetime, date


class OOTDLogCreate(BaseModel):
    outfit_id: UUID | None = None
    custom_item_ids: list[UUID] | None = None
    logged_date: date
    note: str | None = None


class OOTDLogResponse(BaseModel):
    id: UUID
    outfit_id: UUID | None
    custom_item_ids: list[UUID] | None
    logged_date: date
    note: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class StreakResponse(BaseModel):
    current_streak: int
    longest_streak: int


class CalendarResponse(BaseModel):
    """Response for calendar query — dates with OOTD logged."""
    dates: list[date]  # Dates with OOTD entries

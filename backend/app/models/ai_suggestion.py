import uuid
from datetime import datetime, timezone

from sqlalchemy import String, DateTime, Boolean, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class AISuggestion(Base):
    """
    Persisted AI outfit suggestions for a user.

    One row per user (upserted on regenerate).
    `suggestions` is the full list of rich suggestion dicts as JSONB.
    `wardrobe_hash` is an md5 of sorted item IDs — used to detect
    when the wardrobe has changed since the last generation.
    `is_stale` is set True when new items are added; Flutter shows
    a "Refresh for new suggestions" banner.
    """
    __tablename__ = "ai_suggestions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True, unique=True
    )
    suggestions: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    occasion: Mapped[str | None]  = mapped_column(String(100), nullable=True)
    season:   Mapped[str | None]  = mapped_column(String(50),  nullable=True)
    wardrobe_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    is_stale: Mapped[bool] = mapped_column(Boolean, default=False)
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

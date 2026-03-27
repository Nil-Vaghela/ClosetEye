import uuid
from datetime import datetime, timezone
from enum import Enum as PyEnum

from sqlalchemy import String, DateTime, ForeignKey, Float, Enum
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ClothingCategory(str, PyEnum):
    TOP = "top"
    BOTTOM = "bottom"
    OUTERWEAR = "outerwear"
    DRESS = "dress"
    SHOES = "shoes"
    ACCESSORY = "accessory"
    OTHER = "other"


class Season(str, PyEnum):
    SPRING = "spring"
    SUMMER = "summer"
    FALL = "fall"
    WINTER = "winter"
    ALL = "all"


class ClothingItem(Base):
    __tablename__ = "clothing_items"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    # ── Extracted / user-provided metadata ──────────────────
    name: Mapped[str] = mapped_column(String(255), nullable=True)
    category: Mapped[str] = mapped_column(Enum(ClothingCategory), nullable=False)
    color_primary: Mapped[str] = mapped_column(String(50), nullable=True)  # hex or name
    color_secondary: Mapped[str] = mapped_column(String(50), nullable=True)
    brand: Mapped[str] = mapped_column(String(255), nullable=True)
    season: Mapped[str] = mapped_column(Enum(Season), default=Season.ALL)
    tags: Mapped[list] = mapped_column(ARRAY(String), default=list)  # e.g. ["casual", "work"]

    # ── Images ──────────────────────────────────────────────
    original_image_url: Mapped[str] = mapped_column(String(512), nullable=False)
    cleaned_image_url: Mapped[str] = mapped_column(String(512), nullable=True)  # bg-removed / dewrinkled

    # ── AI-generated embeddings (for mix-match scoring) ─────
    style_score: Mapped[float] = mapped_column(Float, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # relationships
    owner = relationship("User", back_populates="clothing_items")

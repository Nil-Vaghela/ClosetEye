import uuid
from datetime import datetime, timezone

from sqlalchemy import String, DateTime, ForeignKey, Float, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Outfit(Base):
    """A saved outfit combination."""
    __tablename__ = "outfits"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=True)
    occasion: Mapped[str] = mapped_column(String(100), nullable=True)  # e.g. "work", "date night"
    match_score: Mapped[float] = mapped_column(Float, nullable=True)  # AI-generated compatibility score
    is_ai_suggested: Mapped[bool] = mapped_column(Boolean, default=False)
    preview_image_url: Mapped[str] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # relationships
    owner = relationship("User", back_populates="outfits")
    items = relationship("OutfitItem", back_populates="outfit", cascade="all, delete-orphan")


class OutfitItem(Base):
    """Junction table linking outfits to clothing items."""
    __tablename__ = "outfit_items"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    outfit_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("outfits.id"), nullable=False)
    clothing_item_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("clothing_items.id"), nullable=False)
    layer_order: Mapped[int] = mapped_column(default=0)  # for rendering order in try-on

    outfit = relationship("Outfit", back_populates="items")
    clothing_item = relationship("ClothingItem")

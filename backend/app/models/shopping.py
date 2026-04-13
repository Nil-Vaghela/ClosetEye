"""
Shopping Item Model
===================
Represents temporary "shopping" items (items from external links/photos that user wants to try).
Expires after 30 days to auto-cleanup.
"""
import uuid
from datetime import datetime, timezone, timedelta

from sqlalchemy import String, DateTime, ForeignKey, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.clothing import ClothingCategory


class ShoppingItem(Base):
    """A clothing item from a shopping link (temporary, 30-day expiry)."""

    __tablename__ = "shopping_items"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    # Clothing attributes
    name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    category: Mapped[str] = mapped_column(Enum(ClothingCategory), nullable=False)
    color_primary: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # Images
    original_image_url: Mapped[str] = mapped_column(String(512), nullable=False)
    cleaned_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)

    # Auto-expire after 30 days
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc) + timedelta(days=30),
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    owner = relationship("User")

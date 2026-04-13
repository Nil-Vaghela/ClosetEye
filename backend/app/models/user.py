import uuid
from datetime import datetime, timezone

from sqlalchemy import String, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Phone auth (Firebase)
    phone_number: Mapped[str] = mapped_column(String(20), unique=True, index=True, nullable=False)
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)

    # Profile — filled in during onboarding
    full_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)

    # Body model — created in Sprint 2, used for virtual try-on
    body_photo_url: Mapped[str | None] = mapped_column(String(512), nullable=True)   # original reference photo
    body_silhouette_url: Mapped[str | None] = mapped_column(String(512), nullable=True)  # processed cutout
    height_cm: Mapped[int | None] = mapped_column(nullable=True)
    weight_kg: Mapped[int | None] = mapped_column(nullable=True)
    body_type: Mapped[str | None] = mapped_column(String(32), nullable=True)  # slim / regular / athletic / curvy / plus
    body_model_ready: Mapped[bool] = mapped_column(default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    clothing_items = relationship("ClothingItem", back_populates="owner", cascade="all, delete-orphan")
    outfits = relationship("Outfit", back_populates="owner", cascade="all, delete-orphan")
    ootd_logs = relationship("OOTDLog", back_populates="user", cascade="all, delete-orphan")

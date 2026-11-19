"""
Outfit Engine models — Daily Outfits, Feedback, Style Preferences, Outfit History
These power the Daily Outfit Engine, Feedback Loop, Memory System, and Notifications.
"""
import uuid
from datetime import datetime, date, timezone

from sqlalchemy import String, DateTime, Date, Text, Float, Integer, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class DailyOutfit(Base):
    """
    Cached daily outfit suggestions generated per user per day.
    Checked before AI generation to avoid recomputing.
    """
    __tablename__ = "daily_outfits"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # Date the suggestions are for (not created_at)
    outfit_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)

    # Occasion filter used when generating (nullable = no filter)
    occasion: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # Weather snapshot at generation time
    weather_temp_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    weather_condition: Mapped[str | None] = mapped_column(String(100), nullable=True)  # "sunny", "rainy", etc.
    weather_location: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Full outfit suggestions array (JSON)
    # [{items: {top, bottom, shoes, jacket}, confidence_score, breakdown, reason}, ...]
    outfits_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=list)

    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # Relationship
    user = relationship("User")


class OutfitHistory(Base):
    """
    Tracks outfits the user actually wore (logged via 'I wore this').
    Used to prevent repetition, detect overused items, and build analytics.
    """
    __tablename__ = "outfit_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # Optional reference to a saved outfit (null if it was an ad-hoc combination)
    outfit_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("outfits.id"), nullable=True)

    # Snapshot of items worn — {top: uuid, bottom: uuid, shoes: uuid, jacket: uuid}
    # Stored as JSON so we have the exact combo even if items are later deleted
    items_snapshot: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # Item IDs as a flat list for fast "worn recently" queries
    item_ids: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    worn_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    occasion: Mapped[str | None] = mapped_column(String(50), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    user = relationship("User")
    outfit = relationship("Outfit")


class OutfitFeedback(Base):
    """
    User feedback on outfit suggestions (👍/👎).
    Drives the preference weight updates in UserStylePreferences.
    """
    __tablename__ = "outfit_feedback"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    # Reference to the DailyOutfit that was suggested
    daily_outfit_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("daily_outfits.id"), nullable=True)

    # Snapshot of item IDs that were in the outfit
    item_ids: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    # Color pair snapshot e.g. ["navy", "white"]
    color_pair: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    # Category pair snapshot e.g. ["top", "bottom"]
    category_pair: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    feedback: Mapped[str] = mapped_column(String(10), nullable=False)  # "like" | "dislike"
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    user = relationship("User")


class UserStylePreferences(Base):
    """
    Evolving preference weights per user — updated automatically when feedback is submitted.
    Used in the confidence scoring and outfit generation ranking.
    """
    __tablename__ = "user_style_preferences"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True, index=True)

    # Color affinity scores — key: "color1:color2" sorted alphabetically, value: weight (-1.0 to 1.0)
    # Positive = user likes this combo, negative = penalize
    color_pair_weights: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # Category combo weights — key: "category1:category2", value: weight
    category_weights: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # Occasion preferences — key: occasion string, value: frequency count
    occasion_counts: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # "never pair these": sorted "item_a:item_b" keys that must never be suggested together
    blocked_item_pairs: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    # Total feedbacks processed — used to normalize
    total_likes: Mapped[int] = mapped_column(Integer, default=0)
    total_dislikes: Mapped[int] = mapped_column(Integer, default=0)

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    user = relationship("User")


class NotificationLog(Base):
    """
    Tracks sent notifications to prevent duplicates and enable analytics.
    """
    __tablename__ = "notification_logs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    notification_type: Mapped[str] = mapped_column(String(50), nullable=False)
    # "morning_outfit" | "weather_mismatch" | "unused_item" | "repetition_warning"

    title: Mapped[str] = mapped_column(String(255), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)

    # Optional metadata (item_id for unused_item, etc.)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)

    user = relationship("User")

"""Full account deletion (App Store guideline 5.1.1(v))."""
import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.services import storage

logger = logging.getLogger(__name__)

# Order matters (children before parents). (table, owner column)
_USER_TABLES = [
    ("outfit_feedback", "user_id"),
    ("daily_outfits", "user_id"),
    ("outfit_history", "user_id"),
    ("ootd_logs", "user_id"),
    ("notification_logs", "user_id"),
    ("user_style_preferences", "user_id"),
    ("ai_usage", "user_id"),
    ("ai_suggestions", "owner_id"),
    ("shopping_items", "owner_id"),
]


async def delete_account(db: AsyncSession, user: User) -> None:
    uid = user.id
    firebase_uid = user.firebase_uid
    for table, col in _USER_TABLES:
        await db.execute(text(f"DELETE FROM {table} WHERE {col} = :uid"), {"uid": uid})
    await db.execute(text(
        "DELETE FROM outfit_items WHERE outfit_id IN (SELECT id FROM outfits WHERE owner_id = :uid)"
    ), {"uid": uid})
    await db.execute(text("DELETE FROM outfits WHERE owner_id = :uid"), {"uid": uid})
    await db.execute(text("DELETE FROM clothing_items WHERE owner_id = :uid"), {"uid": uid})
    await db.execute(text("DELETE FROM users WHERE id = :uid"), {"uid": uid})
    await db.commit()

    removed = storage.delete_tree_for_user(uid)
    logger.info("Account deleted (%s files removed)", removed)

    try:
        from firebase_admin import auth as fb_auth
        from app.services.firebase_auth import _init_firebase
        _init_firebase()
        fb_auth.delete_user(firebase_uid)
    except Exception as exc:  # app also deletes its Firebase user client-side
        logger.warning("Firebase user delete skipped: %s", type(exc).__name__)

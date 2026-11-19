"""Deleting a wardrobe item safely (no FK errors, no orphaned outfits)."""
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.clothing import ClothingItem
from app.models.ootd import OOTDLog
from app.models.outfit import Outfit, OutfitItem
from app.models.outfit_engine import OutfitHistory


async def remove_item_everywhere(db: AsyncSession, item: ClothingItem) -> list:
    """Remove the item from outfits, delete outfits left empty, then delete the item.
    Wear history keeps its JSON snapshot. Caller commits. Returns deleted outfit ids."""
    affected = (await db.execute(
        select(OutfitItem.outfit_id).where(OutfitItem.clothing_item_id == item.id)
    )).scalars().all()

    await db.execute(delete(OutfitItem).where(OutfitItem.clothing_item_id == item.id))

    emptied = []
    if affected:
        still_used = set((await db.execute(
            select(OutfitItem.outfit_id).where(OutfitItem.outfit_id.in_(affected))
            .group_by(OutfitItem.outfit_id).having(func.count() > 0)
        )).scalars().all())
        emptied = [o for o in set(affected) if o not in still_used]
        if emptied:
            await db.execute(update(OutfitHistory).where(OutfitHistory.outfit_id.in_(emptied)).values(outfit_id=None))
            await db.execute(update(OOTDLog).where(OOTDLog.outfit_id.in_(emptied)).values(outfit_id=None))
            await db.execute(delete(Outfit).where(Outfit.id.in_(emptied)))

    await db.delete(item)
    return emptied

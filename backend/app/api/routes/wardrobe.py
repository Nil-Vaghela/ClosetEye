from uuid import UUID
import asyncio
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.config import settings
from app.api.deps import get_current_user
from app.models.user import User
from app.models.clothing import ClothingItem, ClothingCategory, Season
from app.models.ai_suggestion import AISuggestion
from app.schemas.clothing import ClothingItemResponse, ClothingItemUpdate
from app.services.file_service import file_service
from app.services.garment_service import (
    extract_garment, dewrinkle_and_clean, detect_photo_type_heuristic,
    crop_item_from_photo, isolate_person, crop_item_by_category,
)
from app.services.ai_service import ai_service

logger = logging.getLogger(__name__)
router = APIRouter()


def _sniff_mime(data: bytes, fallback: str = "unknown") -> str:
    """Detect real MIME type from magic bytes.
    Flutter/mobile often sends application/octet-stream regardless of format."""
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[4:8] in (b"ftyp", b"heic", b"heix"):
        return "image/heic"
    return fallback


@router.post("/items", response_model=ClothingItemResponse, status_code=201)
async def upload_clothing_item(
    image: UploadFile = File(...),
    category: ClothingCategory | None = Form(None),
    name: str | None = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Upload a photo of a clothing item.
    The backend will:
    1. Save the original image
    2. Detect photo type (worn vs flatlay)
    3. Extract the clothing from the background
    4. Dewrinkle and clean
    5. AI attribute detection (color, category, tags, pattern)
    6. Store the cleaned version with attributes

    Form parameters:
    - image: image file (JPEG, PNG, WEBP, HEIC)
    - category: optional override for detected category
    - name: optional item name
    """
    # ── 1. Validate file type and size ──────────────────────────────────────────
    image_bytes = await image.read()

    detected_mime = _sniff_mime(image_bytes, fallback=image.content_type or "unknown")
    allowed_types = {"image/jpeg", "image/png", "image/webp", "image/heic"}
    if detected_mime not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type '{detected_mime}'. Use JPEG, PNG, or WEBP.",
        )
    max_bytes = settings.MAX_FILE_SIZE_MB * 1024 * 1024
    if len(image_bytes) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image must be under {settings.MAX_FILE_SIZE_MB} MB.",
        )

    try:
        # ── 2. Save original image ─────────────────────────────────────────────
        logger.info(f"Saving original image for user {current_user.id}")
        _, original_url = await file_service.save(
            image_bytes,
            f"garments/{current_user.id}/original",
            "jpg",
        )

        # ── 3. Detect photo type (worn vs flatlay) ────────────────────────────
        logger.info("Detecting photo type")
        photo_type = detect_photo_type_heuristic(image_bytes)

        # ── 4. Extract garment (background removal) ───────────────────────────
        logger.info("Extracting garment with rembg")
        garment_bytes = extract_garment(image_bytes, photo_type)

        # ── 5. Dewrinkle and clean ────────────────────────────────────────────
        logger.info("Dewrinkling and cleaning")
        cleaned_bytes = dewrinkle_and_clean(garment_bytes)

        # ── 6. Save cleaned image ──────────────────────────────────────────────
        logger.info("Saving cleaned image")
        _, cleaned_url = await file_service.save(
            cleaned_bytes,
            f"garments/{current_user.id}/cleaned",
            "png",
        )

        # ── 7. AI attribute detection ──────────────────────────────────────────
        logger.info("Running AI attribute detection")
        try:
            attributes = await ai_service.detect_attributes(cleaned_bytes)
        except Exception as exc:
            logger.warning(f"AI attribute detection failed: {exc}; using defaults")
            attributes = {
                "name": name,
                "category": category or "other",
                "color_primary": None,
                "color_secondary": None,
                "season": "all",
                "tags": [],
                "pattern": None,
            }

        # ── 8. Map attributes to enums with fallbacks ─────────────────────────
        detected_category = category or attributes.get("category", "other")
        try:
            detected_category = ClothingCategory(detected_category)
        except ValueError:
            detected_category = ClothingCategory.OTHER

        detected_season = attributes.get("season", "all")
        try:
            detected_season = Season(detected_season)
        except ValueError:
            detected_season = Season.ALL

        # ── 9. Prepend pattern to tags ─────────────────────────────────────────
        tags = attributes.get("tags", [])
        if isinstance(tags, str):
            tags = [tags]
        pattern = attributes.get("pattern")
        if pattern and pattern not in tags:
            tags = [pattern] + tags
        tags = tags[:4]  # Max 4 tags

        # ── 10. Persist to database ────────────────────────────────────────────
        logger.info("Creating ClothingItem in database")
        item = ClothingItem(
            owner_id=current_user.id,
            name=name or attributes.get("name"),
            category=detected_category,
            color_primary=attributes.get("color_primary"),
            color_secondary=attributes.get("color_secondary"),
            season=detected_season,
            tags=tags,
            original_image_url=original_url,
            cleaned_image_url=cleaned_url,
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)

        logger.info(f"Item created: {item.id}")

        # ── 11. Mark existing AI suggestions stale ─────────────────────────────
        try:
            sug_result = await db.execute(
                select(AISuggestion).where(AISuggestion.owner_id == current_user.id)
            )
            ai_sug = sug_result.scalar_one_or_none()
            if ai_sug:
                ai_sug.is_stale = True
                await db.commit()
        except Exception as exc:
            logger.warning(f"Could not mark suggestions stale: {exc}")

        return item

    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"Upload failed: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Upload processing failed: {str(exc)}",
        ) from exc


@router.get("/items", response_model=list[ClothingItemResponse])
async def list_clothing_items(
    category: ClothingCategory | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all items in the user's wardrobe, optionally filtered by category."""
    query = select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    if category:
        query = query.where(ClothingItem.category == category)
    result = await db.execute(query.order_by(ClothingItem.created_at.desc()))
    return result.scalars().all()


@router.get("/items/{item_id}", response_model=ClothingItemResponse)
async def get_clothing_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@router.patch("/items/{item_id}", response_model=ClothingItemResponse)
async def update_clothing_item(
    item_id: UUID,
    payload: ClothingItemUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    await db.commit()
    await db.refresh(item)
    return item


@router.delete("/items/{item_id}", status_code=204)
async def delete_clothing_item(
    item_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ClothingItem).where(
            ClothingItem.id == item_id, ClothingItem.owner_id == current_user.id
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    # Clean up image files
    try:
        if item.original_image_url:
            await file_service.delete(item.original_image_url)
        if item.cleaned_image_url:
            await file_service.delete(item.cleaned_image_url)
    except Exception as exc:
        logger.warning(f"Failed to clean up files: {exc}")

    await db.delete(item)
    await db.commit()


# ── Analysis endpoints ─────────────────────────────────────────────────────


@router.get("/style-dna")
async def get_style_dna(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Analyze user's clothing style and return dominant style traits."""
    # Fetch all items
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    )
    items = result.scalars().all()

    # Convert to dicts for AI analysis
    items_data = [
        {
            "id": str(item.id),
            "name": item.name,
            "category": item.category,
            "color_primary": item.color_primary,
            "color_secondary": item.color_secondary,
            "tags": item.tags,
            "season": item.season,
        }
        for item in items
    ]

    # Get analysis from AI
    analysis = await ai_service.analyze_style_dna(items_data)
    return analysis


@router.get("/capsule-score")
async def get_capsule_score(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get capsule wardrobe score and category breakdown."""
    # Fetch all items
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    )
    items = result.scalars().all()

    items_data = [{"category": item.category} for item in items]

    # Calculate score
    score = await ai_service.calculate_capsule_score(items_data)

    # Breakdown by category
    from collections import Counter

    category_count = Counter(item.category for item in items)

    return {
        "score": score,
        "breakdown": dict(category_count),
    }


@router.get("/cost-per-wear")
async def get_cost_per_wear(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    List items with cost-per-wear analysis.
    Requires 'price' and 'total_wears' fields on items.
    """
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    )
    items = result.scalars().all()

    items_with_cpw = []
    for item in items:
        price = getattr(item, "price", None)
        total_wears = getattr(item, "total_wears", 0)

        cpw = None
        if price and total_wears > 0:
            cpw = price / total_wears

        items_with_cpw.append({
            "id": str(item.id),
            "name": item.name,
            "category": item.category,
            "price": price,
            "total_wears": total_wears,
            "cost_per_wear": cpw,
        })

    # Sort by cost per wear (lowest first)
    items_with_cpw.sort(
        key=lambda x: x["cost_per_wear"] if x["cost_per_wear"] else float("inf")
    )

    return items_with_cpw


@router.get("/gap-analysis")
async def get_gap_analysis(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get suggestions for items to buy to unlock more outfit combinations."""
    # Fetch all items
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    )
    items = result.scalars().all()

    items_data = [
        {
            "id": str(item.id),
            "name": item.name,
            "category": item.category,
            "color_primary": item.color_primary,
            "tags": item.tags,
        }
        for item in items
    ]

    # Get analysis from AI
    analysis = await ai_service.wardrobe_gap_analysis(items_data)
    return analysis


@router.get("/shopping-suggestions")
async def get_shopping_suggestions(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get shopping suggestions based on wardrobe gaps."""
    # Same as gap-analysis for now
    result = await db.execute(
        select(ClothingItem).where(ClothingItem.owner_id == current_user.id)
    )
    items = result.scalars().all()

    items_data = [
        {
            "id": str(item.id),
            "name": item.name,
            "category": item.category,
            "color_primary": item.color_primary,
            "tags": item.tags,
        }
        for item in items
    ]

    analysis = await ai_service.wardrobe_gap_analysis(items_data)
    return analysis


# ── Multi-item extraction ────────────────────────────────────────────────────


@router.post("/extract-items")
async def extract_items_from_photo(
    image: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Extract ALL visible clothing items from a single photo.

    Pipeline:
    1. Save original
    2. GPT-4V → detect items + metadata
    3. rembg on FULL photo → isolate person (no trees, poles, cars)
    4. Crop each CLOTHING item by category body zone
    5. Place on white background → professional product shot
    6. Skip accessories (sunglasses, watch, necklace) — too small to crop
    """
    image_bytes = await image.read()

    detected_mime = _sniff_mime(image_bytes)
    allowed = {"image/jpeg", "image/png", "image/webp", "image/heic"}
    if detected_mime not in allowed:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported image type '{detected_mime}'.",
        )

    # Save original photo
    _, original_url = await file_service.save(
        image_bytes, f"garments/{current_user.id}/original", "jpg",
    )

    # GPT-4V: detect every visible clothing item (NOT accessories)
    logger.info("Detecting all items in photo via GPT-4V")
    items: list[dict] = await ai_service.detect_all_items(image_bytes)
    if not items:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No clothing items could be detected in this photo.",
        )

    # ── Step 2: Filter to main clothing items only ───────────────────────
    CLOTHING_CATS = {"top", "bottom", "outerwear", "dress", "shoes"}
    clothing_items = [
        item for item in items
        if (item.get("category") or "other").lower() in CLOTHING_CATS
    ]
    if not clothing_items:
        clothing_items = items  # fallback: keep all

    # ── Step 3: GPT-4V precision description → DALL-E 3 HD product image ─
    # For each garment, GPT-4V writes a 50-word exact description of how
    # that specific garment looks in the photo, then DALL-E 3 HD generates
    # a matching flat-lay product shot on clean gray background.
    logger.info(f"Generating precision product images for {len(clothing_items)} items")

    async def _gen_product(item_data: dict) -> dict:
        try:
            product_bytes = await ai_service.generate_product_image(
                attributes=item_data,
                full_photo_bytes=image_bytes,
            )
            if product_bytes:
                _, url = await file_service.save(
                    product_bytes,
                    f"garments/{current_user.id}/extracted",
                    "png",
                )
                item_data["product_image_url"] = url
            else:
                item_data["product_image_url"] = None
        except Exception as exc:
            logger.warning(f"Product image failed for '{item_data.get('name')}': {exc}")
            item_data["product_image_url"] = None
        return item_data

    results = await asyncio.gather(*[_gen_product(item) for item in clothing_items])
    logger.info(f"Extraction complete: {len(results)} items")
    return {"original_image_url": original_url, "items": results}


class _BatchItem(BaseModel):
    name: str | None = None
    category: str = "other"
    subcategory: str | None = None
    color_primary: str | None = None
    color_secondary: str | None = None
    color: list[str] = []
    season: str = "all"
    tags: list[str] = []
    pattern: str | None = None
    material: str | None = None
    fit: str | None = None
    attributes: dict = {}
    confidence: float = 1.0
    product_image_url: str | None = None


class _BatchAddRequest(BaseModel):
    original_image_url: str
    items: list[_BatchItem]


@router.post("/batch-add", response_model=list[ClothingItemResponse], status_code=201)
async def batch_add_items(
    payload: _BatchAddRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Add multiple extracted items to the wardrobe in one call.

    Called after POST /extract-items — the client sends back the
    original photo URL and the subset of items the user selected.
    """
    created: list[ClothingItem] = []

    for item_data in payload.items:
        try:
            cat = ClothingCategory(item_data.category)
        except ValueError:
            cat = ClothingCategory.OTHER

        try:
            ssn = Season(item_data.season)
        except ValueError:
            ssn = Season.ALL

        # Build rich tag set: pattern + material + fit + subcategory + user tags
        tags: list[str] = []
        for extra in [
            item_data.pattern,
            item_data.material,
            item_data.fit,
            item_data.subcategory,
        ]:
            if extra and extra not in tags:
                tags.append(extra)
        for t in item_data.tags:
            if t not in tags:
                tags.append(t)
        tags = tags[:6]  # keep top 6 most descriptive tags

        # Resolve color_primary: prefer explicit field, fall back to color list
        color_primary = item_data.color_primary
        if not color_primary and item_data.color:
            color_primary = item_data.color[0]
        color_secondary = item_data.color_secondary
        if not color_secondary and len(item_data.color) > 1:
            color_secondary = item_data.color[1]

        item = ClothingItem(
            owner_id=current_user.id,
            name=item_data.name,
            category=cat,
            color_primary=color_primary,
            color_secondary=color_secondary,
            season=ssn,
            tags=tags,
            original_image_url=payload.original_image_url,
            cleaned_image_url=item_data.product_image_url,
        )
        db.add(item)
        created.append(item)

    await db.commit()
    for item in created:
        await db.refresh(item)

    # Mark existing AI suggestions stale (new wardrobe items → refresh needed)
    try:
        sug_result = await db.execute(
            select(AISuggestion).where(AISuggestion.owner_id == current_user.id)
        )
        ai_sug = sug_result.scalar_one_or_none()
        if ai_sug:
            ai_sug.is_stale = True
            await db.commit()
    except Exception as exc:
        logger.warning(f"Could not mark suggestions stale: {exc}")

    logger.info(f"Batch-added {len(created)} items for user {current_user.id}")
    return created

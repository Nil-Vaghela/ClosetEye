# Drape Backend Implementation: Sprints 3-7

## Overview
This document outlines all backend implementations for Sprints 3 through 7 of the Drape AI-powered digital wardrobe application.

## Sprint 3: Wardrobe Core (Smart Upload)

### Files Created

#### 1. **app/services/file_service.py**
- **FileService class** for async file handling
- `save(data: bytes, subdir: str, ext: str) -> (abs_path, public_url)`
  - Saves files to disk using aiofiles
  - Creates directories automatically
  - Returns both absolute path and public URL
- `delete(public_url: str)`
  - Removes files by public URL
  - Graceful error handling

#### 2. **app/services/garment_service.py**
- **PhotoType enum** with WORN and FLATLAY values
- `detect_photo_type_heuristic(image_bytes) -> PhotoType`
  - Uses rembg background removal
  - Calculates bbox aspect ratio (height/width > 1.5 → WORN)
  - Heuristic-based, no API cost
- `extract_garment(image_bytes, photo_type) -> bytes`
  - Removes background via rembg
  - Crops to tight bbox with 3% padding
  - Returns PNG with transparent background
  - Graceful fallback if rembg unavailable
- `dewrinkle_and_clean(image_bytes) -> bytes`
  - UnsharpMask filter (radius=1, percent=120, threshold=3)
  - Contrast boost 1.08 on RGB only (preserves alpha)
  - Returns cleaned PNG bytes
  - Note: Production upgrade would use diffusion model

#### 3. **app/services/ai_service.py** (Fully Implemented)
- **AIService class** with lazy OpenAI client initialization
- `detect_photo_type(image_bytes) -> str`
  - Uses OpenAI Vision gpt-4o-mini
  - Returns "worn" or "flatlay"
  - Falls back to heuristic if no API key
- `detect_attributes(image_bytes) -> dict`
  - Extracts: name, category, color_primary, color_secondary, season, tags, pattern
  - Uses OpenAI Vision with JSON mode
  - Strips markdown code fences from response
  - Returns `_default_attributes()` fallback on error
  - Validates enum values before returning
- `score_outfit(item_image_urls) -> float`
  - Scores outfit compatibility 0-1
  - Returns 0.75 on error
- `suggest_outfits(wardrobe_items, occasion, season) -> list[dict]`
  - Suggests 5 outfit combinations
  - Returns empty list on error
- `analyze_style_dna(wardrobe_items) -> dict`
  - Returns dominant_style, style_scores, summary
- `calculate_capsule_score(wardrobe_items) -> int`
  - Estimates unique outfit combinations (0-999)
  - Simple heuristic: tops × bottoms + outerwear × (tops × bottoms)
- `wardrobe_gap_analysis(wardrobe_items) -> dict`
  - Suggests 3 items that unlock most outfit combos
  - Returns item, reason, color for each suggestion

#### 4. **app/models/clothing.py** (Updated)
- Added `price: float | None` for cost tracking
- Added `total_wears: int` with default 0 for cost-per-wear calculations

#### 5. **app/api/routes/wardrobe.py** (Updated)
- **POST /items** — Complete upload pipeline
  1. Validate file type (JPEG, PNG, WEBP, HEIC) and size
  2. Save original via file_service
  3. Detect photo type heuristic
  4. Extract garment (rembg)
  5. Dewrinkle and clean
  6. Save cleaned image
  7. AI attribute detection
  8. Map to enums with fallbacks
  9. Prepend pattern to tags
  10. Persist to database

- **DELETE /items/{item_id}** — Updated to clean up files

- **GET /style-dna** — Get dominant style traits

- **GET /capsule-score** — Get capsule wardrobe score and breakdown

- **GET /cost-per-wear** — Items with cost-per-wear analysis

- **GET /gap-analysis** — Suggestions for wardrobe gaps

- **GET /shopping-suggestions** — Same as gap-analysis

---

## Sprint 4: Virtual Try-On

### Files Created

#### 1. **app/services/tryon_service.py**
- `composite_try_on(body_silhouette_bytes, garment_bytes) -> bytes`
  - MVP: Simple PIL compositing
  - Resizes garment to 60% of body height
  - Centers horizontally, places at ~25% from top
  - Alpha blending
  - Note: Production would use VITON-HD/OOTDiffusion

- `generate_try_on_preview(user_id, item_ids, db, shopping_item_ids) -> bytes`
  - Fetches body silhouette from user DB via httpx
  - Layers garments by category (bottoms → tops → outerwear)
  - Composites all together
  - Downloads images async via httpx
  - Returns composite PNG

#### 2. **app/api/routes/tryon.py** (Updated)
- **TryOnPreviewRequest** schema with item_ids and optional shopping_item_ids
- **TryOnPreviewResponse** schema with preview_url
- **POST /preview**
  - Validates user has body model ready
  - Generates try-on via tryon_service
  - Saves preview via file_service
  - Returns public URL
  - Returns 400 if no body model

#### 3. **Outfit routes** — Already existed, no changes needed
- Existing **app/api/routes/outfits.py** handles POST/GET/DELETE for outfits

---

## Sprint 5: Shopping Try-On

### Files Created

#### 1. **app/models/shopping.py**
```python
class ShoppingItem(Base):
    id: UUID primary key
    owner_id: UUID FK → users
    name: str nullable
    category: ClothingCategory
    color_primary: str nullable
    original_image_url: str
    cleaned_image_url: str nullable
    expires_at: DateTime (created_at + 30 days, auto-cleanup)
    created_at: DateTime
```

#### 2. **app/schemas/shopping.py**
- **ShoppingItemCreate** with category, name, color_primary
- **ShoppingItemResponse** with all fields

#### 3. **app/api/routes/shopping.py**
- **POST /items** — Same pipeline as wardrobe items
  - Uses same garment extraction + AI detection
  - Saves to shopping/{user_id}/ paths
  - Auto-expires after 30 days

- **GET /items** — Lists non-expired items only
  - Filters by expires_at > now()

- **DELETE /items/{id}** — Removes shopping item and cleans files

#### 4. **app/api/routes/tryon.py** (Updated)
- Extended POST /preview to accept optional `shopping_item_ids` parameter
- Shopping items mixed with wardrobe items in compositing

#### 5. **alembic/versions/c3d5f7a9b1e2_shopping_items.py**
- Creates shopping_items table
- Revises: b2c4e6f8a1d3 (body model migration)

---

## Sprint 6: AI Outfit Engine

### Files Updated

#### 1. **app/services/ai_service.py** (Additional methods)
- Methods listed above under Sprint 3

#### 2. **app/models/clothing.py** (Updated)
- Added `price: float | None` for cost tracking
- Added `total_wears: int = 0` for wear count

#### 3. **app/api/routes/suggestions.py** (Updated)
- **GET /** with optional query params: occasion, season
- Fetches user wardrobe
- Generates 5 outfit suggestions via AI
- Scores each outfit for compatibility
- Returns gap analysis as shopping suggestions

#### 4. **alembic/versions/d4e6f8c2a0b3_add_price_and_wears.py**
- Adds `price` float nullable column to clothing_items
- Adds `total_wears` int default 0 column to clothing_items
- Revises: c3d5f7a9b1e2 (shopping items migration)

---

## Sprint 7: Habit & Engagement Loop

### Files Created

#### 1. **app/models/ootd.py**
```python
class OOTDLog(Base):
    id: UUID primary key
    user_id: UUID FK → users
    outfit_id: UUID FK → outfits (nullable)
    custom_item_ids: ARRAY(UUID) (nullable, if no saved outfit)
    logged_date: Date
    note: str nullable
    created_at: DateTime
```

#### 2. **app/schemas/ootd.py**
- **OOTDLogCreate** with outfit_id, custom_item_ids, logged_date, note
- **OOTDLogResponse** with all fields
- **StreakResponse** with current_streak and longest_streak
- **CalendarResponse** with list of dates with OOTD

#### 3. **app/api/routes/ootd.py**
- **POST /** — Log outfit for a date
  - Requires either outfit_id or custom_item_ids
  - Returns 400 if both missing

- **GET /** — List OOTD history (last 90 days by default)
  - Optional `days` query param

- **GET /streak** — Get current and longest streak
  - Counts consecutive days with OOTD
  - Resets if gap > 1 day

- **GET /calendar** — Calendar view for month
  - Query params: year (e.g. 2026), month (1-12)
  - Returns list of dates with OOTD

#### 4. **alembic/versions/e5f7a9d1b2c4_ootd_logs.py**
- Creates ootd_logs table
- Adds indexes on user_id and logged_date
- Revises: d4e6f8c2a0b3 (price and wears migration)

---

## Updated Core Files

### 1. **app/main.py**
- Added imports for shopping and ootd routers
- Registered new routers:
  - `app.include_router(shopping.router, prefix="/api/v1/shopping", tags=["Shopping"])`
  - `app.include_router(ootd.router, prefix="/api/v1/ootd", tags=["OOTD"])`
- Updated version to "0.3.0"

### 2. **app/models/user.py**
- Added relationship: `ootd_logs = relationship("OOTDLog", ...)`

### 3. **app/schemas/clothing.py**
- Updated **ClothingItemResponse** to include price and total_wears fields

### 4. **app/schemas/outfit.py**
- Made `created_at` optional (datetime | None) for AI-generated suggestions

---

## Database Migrations

Three new migrations in chronological order:

1. **c3d5f7a9b1e2_shopping_items.py**
   - Creates shopping_items table with all columns
   - Down: drops table
   - Revises: b2c4e6f8a1d3

2. **d4e6f8c2a0b3_add_price_and_wears.py**
   - Adds price (float, nullable) to clothing_items
   - Adds total_wears (int, default 0) to clothing_items
   - Safe: checks if columns exist before adding
   - Revises: c3d5f7a9b1e2

3. **e5f7a9d1b2c4_ootd_logs.py**
   - Creates ootd_logs table with all columns
   - Creates indexes on user_id and logged_date
   - Down: drops table and indexes
   - Revises: d4e6f8c2a0b3

---

## API Endpoint Summary

### Wardrobe
- `POST /api/v1/wardrobe/items` — Upload garment
- `GET /api/v1/wardrobe/items` — List items (optional filter by category)
- `GET /api/v1/wardrobe/items/{id}` — Get single item
- `PATCH /api/v1/wardrobe/items/{id}` — Update item
- `DELETE /api/v1/wardrobe/items/{id}` — Delete item
- `GET /api/v1/wardrobe/style-dna` — Style analysis
- `GET /api/v1/wardrobe/capsule-score` — Outfit combination score
- `GET /api/v1/wardrobe/cost-per-wear` — Cost analysis
- `GET /api/v1/wardrobe/gap-analysis` — Shopping gaps
- `GET /api/v1/wardrobe/shopping-suggestions` — Shopping suggestions

### Outfits
- `POST /api/v1/outfits` — Create outfit
- `GET /api/v1/outfits` — List outfits
- `DELETE /api/v1/outfits/{id}` — Delete outfit

### Suggestions
- `GET /api/v1/suggestions?occasion=casual&season=summer` — Get outfit suggestions

### Try-On
- `POST /api/v1/tryon/preview` — Generate try-on preview
  - Body: `{"item_ids": [...], "shopping_item_ids": [...]}`

### Shopping
- `POST /api/v1/shopping/items` — Upload shopping item
- `GET /api/v1/shopping/items` — List shopping items (non-expired)
- `DELETE /api/v1/shopping/items/{id}` — Delete shopping item

### OOTD
- `POST /api/v1/ootd` — Log outfit for date
- `GET /api/v1/ootd` — Get OOTD history
- `GET /api/v1/ootd/streak` — Get streak info
- `GET /api/v1/ootd/calendar?year=2026&month=3` — Calendar view

---

## Error Handling & Fallbacks

### AI Service
- If `OPENAI_API_KEY` not set, uses sensible defaults
- API failures use fallback values (e.g., score 0.75 on error)
- JSON parse errors return default attributes

### File Service
- Creates directories automatically if missing
- Graceful error messages on I/O failures
- Files deleted safely with try/except

### Image Processing
- rembg unavailable → returns original image or error
- PIL operations wrapped in try/except

---

## Production Considerations

### Future Upgrades
- **Dewrinkle**: Replace PIL filters with diffusion model (DDPM, Stable Diffusion)
- **Try-On**: Replace MVP with VITON-HD or OOTDiffusion for realistic warping
- **Background Removal**: Consider paid APIs (remove.bg) for higher quality
- **Storage**: Switch from local filesystem to S3/Cloud Storage
- **Push Notifications**: Add Firebase Cloud Messaging for OOTD streaks (stubs in code)
- **Cost Per Wear**: Auto-track wears via calendar/OOTD logs

### Configuration
- All settings in `app/core/config.py`:
  - `OPENAI_API_KEY` — Enable/disable AI features
  - `BASE_URL` — Configure for production domain
  - `UPLOAD_DIR` — Configure storage location
  - `MAX_FILE_SIZE_MB` — Set upload limits

### Database
- All migrations use idempotent patterns (check `if not exists`)
- Safe rollback via `downgrade()` functions
- Foreign key cascades set up for auto-cleanup

---

## Testing Notes

### Manual Testing Checklist
1. Upload garment → verify original + cleaned saved
2. Verify AI attributes detected correctly
3. Create outfit from items → verify compositing
4. Generate try-on → verify preview URL
5. Upload shopping item → verify expires after 30 days
6. Get style DNA → verify analysis
7. Log OOTD → verify streak calculations
8. Query calendar → verify dates returned

### Required Environment Variables
```
OPENAI_API_KEY=sk-...  # For AI features
DATABASE_URL=postgresql+asyncpg://user:pass@localhost/db
BASE_URL=http://localhost:8000  # or production domain
```

---

## Files Modified Summary

### New Files (11)
1. `app/services/file_service.py`
2. `app/services/garment_service.py`
3. `app/services/tryon_service.py` (new, not in original list)
4. `app/models/shopping.py`
5. `app/models/ootd.py`
6. `app/schemas/shopping.py`
7. `app/schemas/ootd.py`
8. `app/api/routes/shopping.py`
9. `app/api/routes/ootd.py`
10. `alembic/versions/c3d5f7a9b1e2_shopping_items.py`
11. `alembic/versions/d4e6f8c2a0b3_add_price_and_wears.py`
12. `alembic/versions/e5f7a9d1b2c4_ootd_logs.py`

### Updated Files (6)
1. `app/services/ai_service.py` — Full implementation
2. `app/models/clothing.py` — Added price, total_wears
3. `app/models/user.py` — Added ootd_logs relationship
4. `app/api/routes/wardrobe.py` — Full upload pipeline + analysis endpoints
5. `app/api/routes/tryon.py` — Full try-on implementation
6. `app/api/routes/suggestions.py` — Full suggestion implementation
7. `app/api/routes/outfits.py` — No changes (already complete)
8. `app/main.py` — Registered new routers
9. `app/schemas/clothing.py` — Added price, total_wears
10. `app/schemas/outfit.py` — Made created_at optional

---

## Code Quality

- **Type hints**: Full typing throughout (no bare `Any` except in AI responses)
- **Error handling**: Try/except blocks with logging
- **Async/await**: All operations properly async
- **Logging**: Structured logging at INFO/WARNING/ERROR levels
- **Documentation**: Docstrings on all public functions
- **Security**: No hardcoded secrets, all via config
- **Validation**: Input validation with pydantic and FastAPI

---

## Dependencies

No new packages needed to requirements.txt — all used already exist:
- openai (for AI service)
- httpx (for downloading images)
- rembg (for garment extraction)
- PIL/Pillow (for image processing)
- aiofiles (for async file I/O)
- FastAPI, SQLAlchemy, pydantic, etc.

---

End of Implementation Document

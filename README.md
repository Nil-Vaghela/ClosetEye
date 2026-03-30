# Drape

**Your AI-powered digital wardrobe assistant.**

Upload photos of your clothes, get outfit suggestions via AI mix-matching, see what to buy next, and virtually try on outfits — all without opening your closet.

---

## Tech Stack

| Layer     | Tech                                  |
|-----------|---------------------------------------|
| Backend   | Python · FastAPI · SQLAlchemy · Alembic |
| Database  | PostgreSQL 16                         |
| Mobile    | React Native (Expo) · TypeScript      |
| AI        | OpenAI Vision API · Remove.bg         |
| Infra     | Docker Compose                        |

---

## Project Structure

```
Drape/
├── backend/
│   ├── app/
│   │   ├── api/routes/      # auth, wardrobe, outfits, suggestions, tryon
│   │   ├── core/            # config, database, security
│   │   ├── models/          # SQLAlchemy models
│   │   ├── schemas/         # Pydantic request/response schemas
│   │   ├── services/        # AI service layer
│   │   └── utils/
│   ├── alembic/             # DB migrations
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
├── mobile/
│   └── DrapeApp/        # React Native (Expo) app
│       ├── src/
│       │   ├── screens/     # Wardrobe, Outfits, Camera, TryOn, Profile
│       │   ├── navigation/
│       │   ├── services/    # API client
│       │   └── components/
│       └── App.tsx
├── docker-compose.ymlr
└── README.md
```

---

## Quick Start

### Backend

```bash
# 1. Start PostgreSQL + backend
docker compose up -d

# 2. Run migrations
cd backend
alembic upgrade head

# 3. API docs available at:
#    http://localhost:8000/docs
```

### Mobile App

```bash
cd mobile/DrapeApp
npm install
npx expo start
```

Scan the QR code with Expo Go on your phone, or press `i` / `a` for iOS/Android simulator.

---

## API Endpoints (Phase 1)

| Method | Endpoint                    | Description                    |
|--------|-----------------------------|--------------------------------|
| POST   | `/api/v1/auth/register`     | Create account                 |
| POST   | `/api/v1/auth/login`        | Get JWT token                  |
| POST   | `/api/v1/wardrobe/items`    | Upload clothing photo          |
| GET    | `/api/v1/wardrobe/items`    | List wardrobe items            |
| PATCH  | `/api/v1/wardrobe/items/:id`| Update item metadata           |
| DELETE | `/api/v1/wardrobe/items/:id`| Remove item                    |
| POST   | `/api/v1/outfits/`          | Save an outfit combo           |
| GET    | `/api/v1/outfits/`          | List saved outfits             |
| POST   | `/api/v1/suggestions/`      | Get AI outfit suggestions      |
| POST   | `/api/v1/tryon/`            | Virtual try-on                 |

---

## Environment Variables

Copy `backend/.env.example` to `backend/.env` and fill in:

- `DATABASE_URL` — PostgreSQL connection string
- `SECRET_KEY` — random string for JWT signing
- `OPENAI_API_KEY` — for AI features
- `REMOVEBG_API_KEY` — for background removal

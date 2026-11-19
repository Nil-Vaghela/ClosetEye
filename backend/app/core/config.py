from typing import List

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_INSECURE_KEYS = {"", "change-me-in-production", "change-me-to-a-random-string"}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── App ─────────────────────────────────────────────────
    APP_NAME: str = "Drape"
    ENV: str = "dev"  # dev | test | staging | prod
    BASE_URL: str = "http://localhost:8000"  # public origin of this API
    DEBUG: bool = False
    SQL_ECHO: bool = False
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    # Short-lived. The app silently re-exchanges its Firebase ID token when this expires.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24
    SIGNED_URL_TTL_SECONDS: int = 60 * 60 * 6

    # ── Database ────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://closeteye:closeteye@localhost:5432/closeteye"

    # ── CORS (only the website needs it; mobile apps don't use CORS) ─────────
    ALLOWED_ORIGINS: List[str] = []

    # ── Firebase ────────────────────────────────────────────
    FIREBASE_SERVICE_ACCOUNT_PATH: str = "/app/firebase-service-account.json"
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""
    FIREBASE_PROJECT_ID: str = "closeteye-c2c03"  # keyless token verification

    # ── AI provider ─────────────────────────────────────────
    # "vertex" = Google Gemini on Vertex AI (billed to Google Cloud), "openai" = OpenAI.
    # Empty = vertex if VERTEX_PROJECT is set, else openai.
    AI_PROVIDER: str = ""
    VERTEX_PROJECT: str = ""
    VERTEX_LOCATION: str = "global"
    VERTEX_TEXT_MODEL: str = "gemini-3-flash-preview"
    VERTEX_IMAGE_MODEL: str = "gemini-2.5-flash-image"
    VERTEX_IMAGE_FALLBACK_MODEL: str = "gemini-3-pro-image"  # used when the main model is busy (429)
    IMAGE_PROVIDER: str = "openai"  # product photos + outfit boards: "openai" or "vertex"
    VERTEX_TRYON_MODEL: str = "virtual-try-on-001"   # Google's dedicated try-on model
    VERTEX_TRYON_LOCATION: str = "us-central1"

    # ── External AI APIs ────────────────────────────────────
    OPENAI_API_KEY: str = ""
    OPENAI_IMAGE_MODEL: str = "gpt-image-2"  # gpt-image-1 was retired by OpenAI
    REPLICATE_API_TOKEN: str = ""
    REMOVEBG_API_KEY: str = ""
    # IDM-VTON weights are CC BY-NC-SA (non-commercial). Off unless explicitly enabled for dev.
    ENABLE_IDM_VTON: bool = False
    # Scanned photos: AI renders a clean catalog photo of each garment (users strongly prefer
    # this to raw cutouts, which include the person on real-world photos).
    ENABLE_AI_PRODUCT_RENDER: bool = True

    # ── Cost controls ───────────────────────────────────────
    DAILY_AI_BUDGET_USD: float = 15.0
    QUOTA_ITEM_UPLOADS_PER_DAY: int = 60
    QUOTA_EXTRACT_PER_DAY: int = 15
    QUOTA_TRYON_PER_DAY: int = 3
    QUOTA_FLATLAY_PER_DAY: int = 5
    QUOTA_LLM_PER_DAY: int = 30

    # ── Storage ─────────────────────────────────────────────
    UPLOAD_DIR: str = "uploads"
    MAX_FILE_SIZE_MB: int = 10

    # ── App review ──────────────────────────────────────────
    SUPPORT_EMAIL: str = "support@drape.app"

    @property
    def is_prod(self) -> bool:
        return self.ENV in ("prod", "staging")

    @model_validator(mode="after")
    def _refuse_unsafe_prod(self):
        if self.is_prod:
            if self.SECRET_KEY in _INSECURE_KEYS or len(self.SECRET_KEY) < 32:
                raise ValueError("SECRET_KEY must be set to a random value of 32+ chars in prod")
            if self.DEBUG:
                raise ValueError("DEBUG must be false in prod")
            if "*" in self.ALLOWED_ORIGINS:
                raise ValueError("CORS wildcard is not allowed in prod")
            if self.BASE_URL.startswith("http://"):
                raise ValueError("BASE_URL must be https in prod")
        return self


settings = Settings()

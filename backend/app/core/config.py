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

    # ── External AI APIs ────────────────────────────────────
    OPENAI_API_KEY: str = ""
    REPLICATE_API_TOKEN: str = ""
    REMOVEBG_API_KEY: str = ""
    # IDM-VTON weights are CC BY-NC-SA (non-commercial). Off unless explicitly enabled for dev.
    ENABLE_IDM_VTON: bool = False
    # AI re-rendered "product shots" of extracted garments (costly, not the real garment).
    ENABLE_AI_PRODUCT_RENDER: bool = False

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

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    # ── App ─────────────────────────────────────────────────
    APP_NAME: str = "ClosetEye"
    DEBUG: bool = True
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 1 week

    # ── Database ────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://closeteye:closeteye@localhost:5432/closeteye"

    # ── CORS ────────────────────────────────────────────────
    ALLOWED_ORIGINS: List[str] = ["*"]  # lock down in production

    # ── Firebase (Phone Auth) ────────────────────────────────
    # Download service account JSON from Firebase Console:
    #   Project Settings → Service Accounts → Generate new private key
    # Place the file at backend/firebase-service-account.json
    # OR paste the entire JSON as a single line in FIREBASE_SERVICE_ACCOUNT_JSON
    FIREBASE_SERVICE_ACCOUNT_PATH: str = "/app/firebase-service-account.json"
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""  # fallback: raw JSON string

    # ── External AI APIs ────────────────────────────────────
    OPENAI_API_KEY: str = ""
    REMOVEBG_API_KEY: str = ""  # for background removal

    # ── Storage ─────────────────────────────────────────────
    UPLOAD_DIR: str = "uploads"
    MAX_FILE_SIZE_MB: int = 10

    class Config:
        env_file = ".env"


settings = Settings()

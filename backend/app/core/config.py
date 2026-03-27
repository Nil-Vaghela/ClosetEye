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

    # ── External AI APIs ────────────────────────────────────
    OPENAI_API_KEY: str = ""
    REMOVEBG_API_KEY: str = ""  # for background removal

    # ── Storage ─────────────────────────────────────────────
    UPLOAD_DIR: str = "uploads"
    MAX_FILE_SIZE_MB: int = 10

    class Config:
        env_file = ".env"


settings = Settings()

"""
File Service
============
Async file save/delete service for handling image uploads and storage.
Uses aiofiles for non-blocking I/O. Creates necessary directories automatically.
Generates public URLs for uploaded files via settings.BASE_URL.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Tuple

import aiofiles
from app.core.config import settings

logger = logging.getLogger(__name__)


class FileService:
    """Manages file uploads and cleanup with async I/O."""

    def __init__(self, upload_dir: str = None):
        """
        Initialize the file service.

        Args:
            upload_dir: Root upload directory (defaults to settings.UPLOAD_DIR)
        """
        self.upload_dir = Path(upload_dir or settings.UPLOAD_DIR)
        self.base_url = settings.BASE_URL.rstrip("/")

    async def save(self, data: bytes, subdir: str, ext: str) -> Tuple[str, str]:
        """
        Save file bytes to disk and generate a public URL.

        Args:
            data: File bytes to save
            subdir: Subdirectory path (e.g. "garments/user-id/original")
            ext: File extension without dot (e.g. "jpg", "png")

        Returns:
            Tuple of (absolute_path: str, public_url: str)

        Raises:
            IOError: If file cannot be written
        """
        # Build full path
        file_dir = self.upload_dir / subdir
        file_dir.mkdir(parents=True, exist_ok=True)

        # Generate filename with timestamp for uniqueness
        import uuid
        filename = f"{uuid.uuid4()}.{ext}"
        file_path = file_dir / filename

        # Write file asynchronously
        try:
            async with aiofiles.open(file_path, mode="wb") as f:
                await f.write(data)
            logger.info(f"Saved file: {file_path} ({len(data)} bytes)")
        except Exception as exc:
            logger.error(f"Failed to save file {file_path}: {exc}")
            raise IOError(f"Failed to save file: {exc}") from exc

        # Build public URL
        from app.services.storage import stable_url
        public_url = stable_url(f"{subdir}/{filename}")

        return str(file_path), public_url

    async def delete(self, public_url: str) -> None:
        """Delete a stored file by its URL (any host; only paths inside UPLOAD_DIR)."""
        from app.services import storage
        storage.delete(public_url)


file_service = FileService()

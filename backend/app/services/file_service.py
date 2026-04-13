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
        relative_path = f"{subdir}/{filename}"
        public_url = f"{self.base_url}/uploads/{relative_path}"

        return str(file_path), public_url

    async def delete(self, public_url: str) -> None:
        """
        Delete a file by its public URL.

        Args:
            public_url: The full public URL (e.g. http://localhost:8000/uploads/...)

        Raises:
            IOError: If file cannot be deleted
        """
        # Extract relative path from URL
        # URL format: {base_url}/uploads/{relative_path}
        if not public_url.startswith(self.base_url):
            logger.warning(f"URL does not match base URL: {public_url}")
            return

        relative = public_url[len(self.base_url) + len("/uploads/") :]
        file_path = self.upload_dir / relative

        try:
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Deleted file: {file_path}")
            else:
                logger.warning(f"File not found for deletion: {file_path}")
        except Exception as exc:
            logger.error(f"Failed to delete file {file_path}: {exc}")
            raise IOError(f"Failed to delete file: {exc}") from exc


file_service = FileService()

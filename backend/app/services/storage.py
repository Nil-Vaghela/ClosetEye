"""
Private file storage with signed URLs.

Files live under settings.UPLOAD_DIR. The database stores a stable URL
(`{BASE_URL}/uploads/<path>`). Nothing under /uploads is public: every URL the
API returns is signed (`?exp=…&sig=…`) and expires. The server never downloads
images over HTTP; services read bytes straight from storage by path, so client
supplied URLs can't be used to make the server fetch arbitrary hosts.
"""
from __future__ import annotations

import hashlib
import hmac
import time
from pathlib import Path
from urllib.parse import urlparse

from app.core.config import settings

_PREFIX = "/uploads/"


def _root() -> Path:
    return Path(settings.UPLOAD_DIR).resolve()


def rel_path(url: str | None) -> str | None:
    """'<anything>/uploads/a/b.png?x' -> 'a/b.png'. None if it isn't one of ours."""
    if not url:
        return None
    path = urlparse(url).path if "://" in url else url.split("?", 1)[0]
    if not path.startswith(_PREFIX):
        return None
    rel = path[len(_PREFIX):]
    if not rel or ".." in rel.split("/"):
        return None
    return rel


def local_path(url: str | None) -> Path | None:
    rel = rel_path(url)
    if rel is None:
        return None
    p = (_root() / rel).resolve()
    if _root() not in p.parents:
        return None
    return p


def stable_url(rel: str) -> str:
    return f"{settings.BASE_URL.rstrip('/')}{_PREFIX}{rel}"


def normalize_owned(url: str | None, owner_id) -> str | None:
    """Accept a URL from a client only if it points at the caller's own files. Returns the stable URL."""
    rel = rel_path(url)
    if rel is None:
        return None
    parts = rel.split("/")
    if len(parts) < 3 or parts[1] != str(owner_id):
        return None
    p = local_path(url)
    if p is None or not p.is_file():
        return None
    return stable_url(rel)


def _sig(rel: str, exp: int) -> str:
    msg = f"{rel}|{exp}".encode()
    return hmac.new(settings.SECRET_KEY.encode(), msg, hashlib.sha256).hexdigest()[:32]


def sign_url(url: str | None, ttl: int | None = None) -> str | None:
    """Turn a stored URL into a short-lived signed URL. Non-storage URLs pass through."""
    rel = rel_path(url)
    if rel is None:
        return url
    ttl = ttl or settings.SIGNED_URL_TTL_SECONDS
    # Round expiry to the hour so the same image keeps one URL (image caches work).
    exp = (int(time.time()) // 3600 + 1) * 3600 + ttl
    return f"{stable_url(rel)}?exp={exp}&sig={_sig(rel, exp)}"


def verify(rel: str, exp: int, sig: str) -> bool:
    if exp < time.time():
        return False
    return hmac.compare_digest(_sig(rel, exp), sig)


def read_bytes(url: str | None) -> bytes:
    p = local_path(url)
    if p is None or not p.is_file():
        raise FileNotFoundError("Image not found in storage")
    return p.read_bytes()


def delete(url: str | None) -> None:
    p = local_path(url)
    if p is not None and p.is_file():
        p.unlink()


def delete_tree_for_user(user_id) -> int:
    """Remove every stored file that belongs to a user. Returns files removed."""
    removed = 0
    root = _root()
    if not root.exists():
        return 0
    uid = str(user_id)
    for top in root.iterdir():
        d = top / uid
        if top.is_dir() and d.is_dir():
            for f in d.rglob("*"):
                if f.is_file():
                    f.unlink()
                    removed += 1
            # Directories may be virtual on Cloud Storage mounts; removing them is best effort.
            for sub in sorted(d.rglob("*"), reverse=True):
                if sub.is_dir():
                    try:
                        sub.rmdir()
                    except OSError:
                        pass
            try:
                d.rmdir()
            except OSError:
                pass
    return removed

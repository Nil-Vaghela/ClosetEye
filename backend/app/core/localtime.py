"""User local date helpers.

The app sends `X-UTC-Offset: <minutes>` (e.g. -300 for New York in winter) on
every request so "today" means the user's today, not the server's.
"""
from datetime import date, datetime, timedelta, timezone

from fastapi import Header


def local_today(x_utc_offset: int | None = Header(default=None, ge=-840, le=840)) -> date:
    offset = timedelta(minutes=x_utc_offset or 0)
    return (datetime.now(timezone.utc) + offset).date()

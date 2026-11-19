"""Serves stored files only with a valid, unexpired signature."""
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.services import storage

router = APIRouter()


@router.get("/uploads/{rel:path}", include_in_schema=False)
async def get_file(rel: str, exp: int = Query(...), sig: str = Query(..., max_length=64)):
    if not storage.verify(rel, exp, sig):
        raise HTTPException(status_code=403, detail="This link has expired.")
    path = storage.local_path("/uploads/" + rel)
    if path is None or not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, headers={"Cache-Control": "private, max-age=3600"})

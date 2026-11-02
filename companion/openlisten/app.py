import asyncio
import secrets
import shutil
from contextlib import asynccontextmanager, suppress
from pathlib import Path
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from .library import Library
from .sources import canonical_source, inspect_source


class ImportRequest(BaseModel):
    urls: list[str] = Field(min_length=1, max_length=10)
    maxEntries: int = Field(default=50, ge=1, le=50)


def create_app(directory: Path, token: str, *, inspector=inspect_source, run_worker=True):
    if len(token) < 24:
        raise ValueError("The pairing token must contain at least 24 characters.")
    library = Library(directory)
    importing = asyncio.Lock()

    @asynccontextmanager
    async def lifespan(app):
        worker = asyncio.create_task(library.run()) if run_worker else None
        yield
        if worker:
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker
        library.db.close()

    async def authorize(authorization: Annotated[str | None, Header()] = None):
        provided = authorization.removeprefix("Bearer ") if authorization else ""
        if not secrets.compare_digest(provided.encode(), token.encode()):
            raise HTTPException(401, "配對碼不正確，請檢查連線設定。")

    app = FastAPI(title="OpenListen", lifespan=lifespan, docs_url=None, redoc_url=None,
                  openapi_url=None, dependencies=[Depends(authorize)])
    app.state.library = library

    @app.get("/v1/health")
    async def health():
        return {"name": "OpenListen", "version": "0.1.0", "ffmpeg": bool(shutil.which("ffmpeg"))}

    @app.get("/v1/tracks")
    async def tracks():
        return library.tracks()

    @app.post("/v1/imports")
    async def import_sources(request: ImportRequest):
        try:
            urls = list(dict.fromkeys(canonical_source(url) for url in request.urls))
        except ValueError as error:
            raise HTTPException(422, str(error)) from error
        if not shutil.which("ffmpeg"):
            raise HTTPException(503, "電腦尚未安裝 FFmpeg，請先完成安裝步驟。")
        if importing.locked():
            raise HTTPException(409, "正在讀取另一份清單，請稍後再加入。")
        async with importing:
            imported, failures = [], []
            remaining = request.maxEntries
            for url in urls:
                if remaining <= 0:
                    break
                try:
                    entries = await inspector(url, remaining)
                    added = library.add(entries)
                    imported.extend(added)
                    remaining -= len(added)
                    if not entries:
                        failures.append({"url": url, "message": "找不到可處理的影片。"})
                except (ValueError, TimeoutError, OSError) as error:
                    message = str(error) if isinstance(error, ValueError) else "來源讀取失敗或逾時。"
                    failures.append({"url": url, "message": message})
            return {"tracks": list({item["id"]: item for item in imported}.values()),
                    "failures": failures, "limit": request.maxEntries}

    def require_track(identifier: UUID):
        item = library.get(str(identifier))
        if not item:
            raise HTTPException(404, "找不到這項音訊。")
        return item

    @app.get("/v1/tracks/{identifier}/audio")
    async def audio(identifier: UUID):
        item = require_track(identifier)
        path = library.audio_path(str(identifier))
        if item["state"] != "ready" or not path.is_file():
            raise HTTPException(409, "音訊尚未準備完成。")
        return FileResponse(path, media_type="audio/mp4", filename=f"{identifier}.m4a")

    @app.post("/v1/tracks/{identifier}/retry")
    async def retry(identifier: UUID):
        item = require_track(identifier)
        if item["state"] != "failed":
            raise HTTPException(409, "只有失敗項目可以重試。")
        library.update(str(identifier), state="queued", error=None)
        return library.get(str(identifier))

    @app.delete("/v1/tracks/{identifier}", status_code=204)
    async def delete(identifier: UUID):
        require_track(identifier)
        library.delete(str(identifier))

    return app

import asyncio
import json
import os
import shutil
import signal
import sqlite3
import uuid
from pathlib import Path

from .sources import ytdlp_command


class Library:
    def __init__(self, directory: Path):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(directory / "library.sqlite3", check_same_thread=False)
        self.db.execute("CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY, video_id TEXT UNIQUE, data TEXT)")
        self.db.commit()
        self.process = None
        self.active_id = None

    def tracks(self) -> list[dict]:
        return [json.loads(row[0]) for row in self.db.execute("SELECT data FROM tracks ORDER BY rowid DESC")]

    def get(self, identifier: str) -> dict | None:
        row = self.db.execute("SELECT data FROM tracks WHERE id = ?", (identifier,)).fetchone()
        return json.loads(row[0]) if row else None

    def save(self, item: dict):
        self.db.execute("INSERT OR REPLACE INTO tracks VALUES (?, ?, ?)",
                        (item["id"], item["videoId"], json.dumps(item)))
        self.db.commit()

    def add(self, entries: list[dict]) -> list[dict]:
        result = []
        for entry in entries:
            row = self.db.execute("SELECT data FROM tracks WHERE video_id = ?", (entry["videoId"],)).fetchone()
            if row:
                item = json.loads(row[0])
            else:
                item = dict(entry, id=str(uuid.uuid4()), state="queued", error=None)
                self.save(item)
            result.append(item)
        return result

    def audio_path(self, identifier: str) -> Path:
        return self.directory / str(uuid.UUID(identifier)) / "audio.m4a"

    def update(self, identifier: str, **changes):
        if item := self.get(identifier):
            item.update(changes)
            self.save(item)

    def delete(self, identifier: str):
        if self.active_id == identifier and self.process and self.process.returncode is None:
            self.stop_process()
        self.db.execute("DELETE FROM tracks WHERE id = ?", (identifier,))
        self.db.commit()
        if self.active_id != identifier:
            shutil.rmtree(self.directory / identifier, ignore_errors=True)

    def stop_process(self):
        if self.process and self.process.returncode is None:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    async def convert(self, item: dict):
        identifier = item["id"]
        target = self.audio_path(identifier)
        self.active_id = identifier
        self.update(identifier, state="processing", error=None)
        try:
            target.parent.mkdir(exist_ok=True)
            target.unlink(missing_ok=True)
            if shutil.disk_usage(self.directory).free < 1024 ** 3:
                raise ValueError("電腦剩餘空間不足 1 GB，請先清理空間。")
            self.process = await asyncio.create_subprocess_exec(
                *ytdlp_command(), "--no-playlist", "--no-progress", "--no-overwrites",
                "--socket-timeout", "20", "--retries", "2", "--fragment-retries", "2",
                "--max-filesize", "300M", "--match-filters", "duration <= 10800 & !is_live",
                "--format", "bestaudio/best", "--extract-audio", "--audio-format", "m4a",
                "--audio-quality", "128K", "--output", str(target.with_suffix(".%(ext)s")),
                "--", item["sourceURL"], stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL, start_new_session=True,
            )
            if not self.get(identifier):
                self.stop_process()
                await self.process.wait()
                return
            await asyncio.wait_for(self.process.wait(), timeout=1800)
            if not self.get(identifier):
                return
            if self.process.returncode or not target.is_file() or target.stat().st_size == 0:
                raise ValueError("未能取得音訊。請檢查來源、更新 yt-dlp，或稍後重試。只接受非直播、3 小時內的內容。")
            self.update(identifier, state="ready", error=None)
        except asyncio.CancelledError:
            self.stop_process()
            if self.process:
                await self.process.wait()
            self.update(identifier, state="queued")
            raise
        except (OSError, ValueError, TimeoutError) as error:
            self.stop_process()
            if self.process:
                await self.process.wait()
            message = str(error) if isinstance(error, ValueError) else "處理中斷或逾時，請稍後重試。"
            self.update(identifier, state="failed", error=message)
        finally:
            if not self.get(identifier) or self.get(identifier)["state"] == "failed":
                shutil.rmtree(target.parent, ignore_errors=True)
            self.process = None
            self.active_id = None

    async def run(self):
        for item in self.tracks():
            if item["state"] == "processing":
                self.update(item["id"], state="queued")
            elif item["state"] == "ready" and not self.audio_path(item["id"]).is_file():
                self.update(item["id"], state="failed", error="電腦上的音檔已被移除，請重新處理。")
        while True:
            queued = [item for item in reversed(self.tracks()) if item["state"] == "queued"]
            if queued:
                await self.convert(queued[0])
            else:
                await asyncio.sleep(0.5)

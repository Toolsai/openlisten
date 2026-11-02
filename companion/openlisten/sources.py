import asyncio
import json
import re
import shutil
import sys
from urllib.parse import parse_qs, quote, unquote, urlencode, urlsplit

VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}\Z")
LIST_ID = re.compile(r"[A-Za-z0-9_-]{10,128}\Z")


def canonical_source(value: str) -> str:
    """Accept YouTube identifiers, never arbitrary fetch URLs or command options."""
    parts = urlsplit(value.strip())
    if parts.scheme not in {"http", "https"} or parts.username or parts.password:
        raise ValueError("請輸入完整的 YouTube 連結。")
    if parts.port not in {None, 80, 443}:
        raise ValueError("不支援這個網址連接埠。")
    host = (parts.hostname or "").lower()
    query = parse_qs(parts.query)
    path = unquote(parts.path).rstrip("/")
    video = None
    if host == "youtu.be":
        video = path.lstrip("/")
    elif host in {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"}:
        if path == "/watch":
            video = query.get("v", [""])[0]
        elif re.fullmatch(r"/(shorts|live|embed)/[A-Za-z0-9_-]{11}", path):
            video = path.rsplit("/", 1)[1]
        elif path == "/playlist" and LIST_ID.fullmatch(query.get("list", [""])[0]):
            return "https://www.youtube.com/playlist?" + urlencode({"list": query["list"][0]})
        elif re.fullmatch(r"/(@[A-Za-z0-9_.\-\u0080-\uffff]{1,100}|channel/UC[A-Za-z0-9_-]{22})(/videos)?", path):
            return "https://www.youtube.com" + quote(path.removesuffix("/videos"), safe="/@-_.") + "/videos"
    if video and VIDEO_ID.fullmatch(video):
        return f"https://www.youtube.com/watch?v={video}"
    raise ValueError("只支援 YouTube 影片、播放清單及頻道連結。")


def ytdlp_command() -> list[str]:
    command = [sys.executable, "-m", "yt_dlp", "--ignore-config", "--no-warnings"]
    if shutil.which("node"):
        command += ["--js-runtimes", "node"]
    return command


async def inspect_source(url: str, limit: int) -> list[dict]:
    process = await asyncio.create_subprocess_exec(
        *ytdlp_command(), "--flat-playlist", "--dump-single-json", "--skip-download",
        "--playlist-end", str(limit), "--socket-timeout", "20", "--", url,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        output, _ = await asyncio.wait_for(process.communicate(), timeout=90)
    except BaseException:
        if process.returncode is None:
            process.kill()
        await process.wait()
        raise
    if process.returncode or len(output) > 8 * 1024 * 1024:
        raise ValueError("無法讀取來源。影片可能已移除、受限制，或來源暫時拒絕連線。")
    try:
        data = json.loads(output)
        entries = data.get("entries") if data.get("_type") == "playlist" else [data]
        result = []
        for entry in (entries or [])[:limit]:
            if not isinstance(entry, dict) or not VIDEO_ID.fullmatch(str(entry.get("id", ""))):
                continue
            if entry.get("is_live") or entry.get("live_status") in {"is_live", "is_upcoming"}:
                continue
            result.append({
                "videoId": entry["id"], "title": str(entry.get("title") or "未命名音訊")[:500],
                "channel": str(entry.get("channel") or entry.get("uploader") or "YouTube")[:200],
                "duration": entry.get("duration") if isinstance(entry.get("duration"), (int, float)) else None,
                "sourceURL": f"https://www.youtube.com/watch?v={entry['id']}",
            })
        return result
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("來源回傳的清單無法讀取。") from error

import asyncio
import shutil
import subprocess
import sys

import pytest
from test_api import ENTRY

from openlisten.library import Library


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="FFmpeg required for the audio fixture")
def test_worker_produces_real_playable_audio(tmp_path, monkeypatch):
    code = """
import pathlib, subprocess, sys
template = sys.argv[sys.argv.index('--output') + 1]
target = template.replace('%(ext)s', 'm4a')
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.2', '-c:a', 'aac', target], check=True)
"""
    monkeypatch.setattr("openlisten.library.ytdlp_command", lambda: [sys.executable, "-c", code])
    library = Library(tmp_path)
    item = library.add([ENTRY])[0]
    asyncio.run(library.convert(item))
    assert library.get(item["id"])["state"] == "ready"
    output = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
        str(library.audio_path(item["id"])),
    ], text=True)
    assert float(output) > 0
    library.db.close()


def test_cancel_removes_record_without_worker_resurrecting_it(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.library.ytdlp_command", lambda: [sys.executable, "-c", "import time; time.sleep(60)"])
    library = Library(tmp_path)
    item = library.add([ENTRY])[0]

    async def scenario():
        task = asyncio.create_task(library.convert(item))
        for _ in range(500):
            if library.process is not None:
                break
            await asyncio.sleep(0.01)
        assert library.process is not None
        library.delete(item["id"])
        await asyncio.wait_for(task, 5)

    asyncio.run(scenario())
    assert library.get(item["id"]) is None
    assert not library.audio_path(item["id"]).parent.exists()
    library.db.close()


def test_failed_command_is_retryable(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.library.ytdlp_command", lambda: [sys.executable, "-c", "raise SystemExit(1)"])
    library = Library(tmp_path)
    item = library.add([ENTRY])[0]
    asyncio.run(library.convert(item))
    assert library.get(item["id"])["state"] == "failed"
    assert library.get(item["id"])["error"]
    assert not library.audio_path(item["id"]).parent.exists()
    library.db.close()


def test_cancel_during_process_creation_still_stops_child(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.library.ytdlp_command", lambda: [sys.executable, "-c", "import time; time.sleep(60)"])
    library = Library(tmp_path)
    item = library.add([ENTRY])[0]
    original = asyncio.create_subprocess_exec

    async def scenario():
        starting, release = asyncio.Event(), asyncio.Event()

        async def delayed(*args, **kwargs):
            starting.set()
            await release.wait()
            return await original(*args, **kwargs)

        monkeypatch.setattr("openlisten.library.asyncio.create_subprocess_exec", delayed)
        task = asyncio.create_task(library.convert(item))
        await asyncio.wait_for(starting.wait(), 5)
        library.delete(item["id"])
        release.set()
        await asyncio.wait_for(task, 5)

    asyncio.run(scenario())
    assert library.get(item["id"]) is None
    assert not library.audio_path(item["id"]).parent.exists()
    library.db.close()


def test_interrupted_output_cannot_be_mistaken_for_completed_audio(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.library.ytdlp_command", lambda: [sys.executable, "-c", "pass"])
    library = Library(tmp_path)
    item = library.add([ENTRY])[0]
    target = library.audio_path(item["id"])
    target.parent.mkdir()
    target.write_bytes(b"unfinished audio from an interrupted process")
    asyncio.run(library.convert(item))
    assert library.get(item["id"])["state"] == "failed"
    assert not target.exists()
    library.db.close()

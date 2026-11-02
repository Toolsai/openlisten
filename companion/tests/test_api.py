from fastapi.testclient import TestClient

from openlisten.app import create_app

TOKEN = "fixture-token-not-a-real-secret-1234"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
ENTRY = {"videoId": "abcdefghijk", "title": "Example", "channel": "Creator",
         "duration": 60, "sourceURL": "https://www.youtube.com/watch?v=abcdefghijk"}


async def inspect(url, limit):
    return [ENTRY]


def test_pairing_required_for_library_and_health(tmp_path):
    with TestClient(create_app(tmp_path, TOKEN, run_worker=False)) as client:
        for path in ["/v1/health", "/v1/tracks"]:
            assert client.get(path).status_code == 401
            assert client.get(path, headers={"Authorization": "Bearer wrong"}).status_code == 401
        assert client.get("/v1/health", headers=HEADERS).status_code == 200


def test_import_deduplicates_and_audio_cannot_be_fetched_early(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.app.shutil.which", lambda _: "/fixture/ffmpeg")
    app = create_app(tmp_path, TOKEN, inspector=inspect, run_worker=False)
    with TestClient(app) as client:
        body = {"urls": ["https://youtu.be/abcdefghijk", "https://youtube.com/watch?v=abcdefghijk"]}
        response = client.post("/v1/imports", json=body, headers=HEADERS)
        assert response.status_code == 200
        tracks = response.json()["tracks"]
        assert len(tracks) == 1
        identifier = tracks[0]["id"]
        assert client.get(f"/v1/tracks/{identifier}/audio", headers=HEADERS).status_code == 409
        assert client.post("/v1/imports", json=body, headers=HEADERS).json()["tracks"][0]["id"] == identifier
        assert len(client.get("/v1/tracks", headers=HEADERS).json()) == 1


def test_audio_range_and_delete(tmp_path):
    app = create_app(tmp_path, TOKEN, run_worker=False)
    item = app.state.library.add([ENTRY])[0]
    audio = app.state.library.audio_path(item["id"])
    audio.parent.mkdir()
    audio.write_bytes(bytes(range(100)))
    app.state.library.update(item["id"], state="ready")
    with TestClient(app) as client:
        route = f"/v1/tracks/{item['id']}"
        assert client.get(route + "/audio").status_code == 401
        response = client.get(route + "/audio", headers=dict(HEADERS, Range="bytes=10-19"))
        assert response.status_code == 206
        assert response.content == bytes(range(10, 20))
        assert response.headers["content-range"] == "bytes 10-19/100"
        assert client.delete(route, headers=HEADERS).status_code == 204
        assert not audio.exists()
        assert client.get(route + "/audio", headers=HEADERS).status_code == 404


def test_batch_reports_partial_failure_and_enforces_total_limit(tmp_path, monkeypatch):
    monkeypatch.setattr("openlisten.app.shutil.which", lambda _: "/fixture/ffmpeg")
    calls = []

    async def partial(url, limit):
        calls.append(url)
        if "bbbbbbbbbbb" in url:
            raise ValueError("unavailable")
        return [ENTRY]

    with TestClient(create_app(tmp_path, TOKEN, inspector=partial, run_worker=False)) as client:
        response = client.post("/v1/imports", headers=HEADERS, json={
            "urls": ["https://youtu.be/bbbbbbbbbbb", "https://youtu.be/abcdefghijk", "https://youtu.be/ccccccccccc"],
            "maxEntries": 1,
        })
        assert len(response.json()["tracks"]) == 1
        assert len(response.json()["failures"]) == 1
        assert len(calls) == 2
        assert client.post("/v1/imports", headers=HEADERS, json={"urls": ["http://localhost"]}).status_code == 422


def test_retry_only_failed_tracks(tmp_path):
    app = create_app(tmp_path, TOKEN, run_worker=False)
    item = app.state.library.add([ENTRY])[0]
    with TestClient(app) as client:
        route = f"/v1/tracks/{item['id']}/retry"
        assert client.post(route, headers=HEADERS).status_code == 409
        app.state.library.update(item["id"], state="failed", error="unavailable")
        assert client.post(route, headers=HEADERS).json()["state"] == "queued"

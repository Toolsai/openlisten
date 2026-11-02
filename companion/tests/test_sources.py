import pytest

from openlisten.sources import canonical_source


@pytest.mark.parametrize("value", [
    "https://youtu.be/abcdefghijk?si=tracking",
    "https://www.youtube.com/watch?v=abcdefghijk&list=PL1234567890",
    "https://m.youtube.com/shorts/abcdefghijk",
    "https://youtube.com/live/abcdefghijk",
])
def test_video_urls_remove_tracking_and_unrequested_playlist(value):
    assert canonical_source(value) == "https://www.youtube.com/watch?v=abcdefghijk"


@pytest.mark.parametrize("value", [
    "file:///etc/passwd", "http://127.0.0.1/admin", "https://youtube.com.evil.example/watch?v=abcdefghijk",
    "https://youtube.com@evil.example/watch?v=abcdefghijk", "--exec=whoami",
    "https://youtube.com:9999/watch?v=abcdefghijk", "https://youtube.com/redirect?q=http://localhost",
    "https://youtu.be/../../etc/passwd", "https://youtube.com/watch?v=short",
])
def test_reject_non_youtube_and_non_media_routes(value):
    with pytest.raises(ValueError):
        canonical_source(value)


def test_channel_and_playlist_are_supported():
    assert canonical_source("https://youtube.com/@example/videos?view=0") == "https://www.youtube.com/@example/videos"
    assert canonical_source("https://youtube.com/playlist?list=PL1234567890&si=secret") == "https://www.youtube.com/playlist?list=PL1234567890"


def test_encoded_channel_handle():
    assert canonical_source("https://youtube.com/@%E4%B8%AD%E6%96%87") == canonical_source("https://youtube.com/@中文")

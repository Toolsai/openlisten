# Acceptance checklist

Automated success is not phone or source acceptance. Record the commit, iPhone model, iOS version, source permissions and observed result for each manual check. Do not add private tokens, copyrighted media or private URLs to issue reports.

## Automated checks

- Companion: accepted YouTube URL forms; rejection of other hosts and local addresses; pairing protection; duplicate imports; partial batch failure; total batch cap; audio Range requests; deletion; retry state; cancellation without record resurrection; a real FFmpeg-generated M4A fixture.
- Core: imported data decoding, preservation of offline files and positions on refresh, persistence round-trip, playlist reference cleanup, private connection address validation, unavailable playback durations.
- CI: iOS app and widget compilation, simulator installation and launch, initial screen screenshot.

## Before calling an installation usable

- [ ] Pair from a real iPhone on the same trusted network; reject an incorrect token.
- [ ] Use a permitted, public source to verify real yt-dlp extraction and audio output.
- [ ] Import a video, playlist and channel; verify the announced 50-item cap and partial failures.
- [ ] Cancel a running conversion; it must stop and not reappear after refresh.
- [ ] Restart the companion during processing; unfinished work should return to the queue.
- [ ] Download two items, lock the phone and listen across the track boundary for one hour.
- [ ] Test lock-screen and headphone play, pause, previous and next.
- [ ] Receive a call and disconnect headphones; check pause/resume behavior.
- [ ] Start a phone download, background the app, interrupt and restore Wi-Fi; check completion and relaunch recovery.
- [ ] Enable airplane mode and play downloaded files; reopen the app and resume saved progress.
- [ ] Create a playlist, reorder and remove entries, relaunch and verify the same order.
- [ ] Add both widget sizes; verify the library and import links open the expected screen.
- [ ] Check large text sizes and VoiceOver button labels.
- [ ] Delete only the phone copy, then download again; separately test complete removal.

Current scope exclusions: complete channel history, streams requiring login, live streams, files over the duration limit, Windows companion, automatic cross-device sync, App Store distribution and production reliability guarantees.

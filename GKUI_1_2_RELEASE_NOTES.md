# Plezy GKUI 1.2.6 — Car Controls and Track Memory

This is the consolidated API 19 / ARMv7 release for the ECARX XE1115H head unit. Phone remote and mirroring are intentionally excluded.

## 1.2.6 car controls and track memory (unreleased)

- Fixes the large GKUI player controls falling back to the stock controller on API 19: the seek bar set `ProgressBar.setMinHeight`, which only exists from API 29. This call, not `setAllCaps` or start/end margins, is the likely cause of the 1.2.4 `NoSuchMethodError`.
- Release builds now fail on any framework call newer than API 19 (Android Lint `NewApi` is fatal), and a GKUI CI workflow builds the API 19 APK, runs lint, and runs the Flutter and Android tests on every push and pull request.
- Audio and subtitle choices made inside the player are now remembered, and are reused by the 720p/480p fallback, Retry, and the next episode.
- A show-level audio or subtitle choice now carries to other episodes by language, since Plex stream IDs differ per episode.
- The CC and Audio buttons show what ExoPlayer actually selected, so CC no longer reads Off while subtitles are showing.
- Network reconnects reset after 30 seconds of steady playback, so each mobile-data dropout gets two fresh retries instead of two per video.
- Same-language audio or subtitle tracks are matched by container order when labels are missing.
- The Audio and CC pickers no longer crash the player if the track list changes while they are open.

## 1.2.5 API 19 player hotfix

- Fixes the `PLAYER_LINKAGE: NoSuchMethodError` reported by the ECARX XE1115H immediately after the stored audio-track choice was loaded.
- Removes direct use of optional start/end-margin and all-caps framework methods that are not consistently present in vendor-modified Android 4.4 builds.
- Exact audio/subtitle selection and the large GKUI controller now fail open: an optional firmware linkage problem is recorded in Status, while video playback continues with language preference or the stock controller fallback.
- Adds setup-stage diagnostics and a sanitized missing-method signature so any remaining vendor-framework incompatibility can be identified from one Status photo.

## 1.2.4 subtitles and car controls

- The subtitle chosen on the media screen is now explicitly matched and selected in ExoPlayer instead of relying only on a language hint.
- External Plex SRT, SSA/ASS, WebVTT, TTML, and TX3G subtitle streams are attached to Direct Play with the authenticated media request.
- The old phone-sized ExoPlayer controls are replaced by a full-width GKUI overlay with large Close, rewind, Play/Pause, forward, Audio, and CC buttons.
- Audio opens a large language/track picker for dual-audio and multi-audio videos; the media-screen choice is also explicitly applied on startup.
- The seek bar spans the display and shows elapsed and total time.
- CC opens a real subtitle-track chooser with 64dp rows and a clear CC On/Off state.
- Subtitles use a larger text size and higher bottom margin for the 800×480 vehicle display.

## 1.2.3 Zurg stream recovery

- Player startup now measures actual HTTP bytes transferred as well as ExoPlayer's decoded buffer progress.
- Playback keeps waiting while either the decoded buffer or network transfer advances, preventing a slow Zurg stream from being mistaken for a dead connection.
- A Direct Play no-frame timeout still automatically retries 720p compatible playback, then 480p safe mode if required.
- Fallback now occurs after 30 seconds only when both decoded-buffer and network-transfer progress have stopped.
- Direct Play has a 90-second safety ceiling; Plex transcodes have 120 seconds for cellular and slow-server startup.
- A player that reports Ready but renders no frame for 10 seconds falls back as a decoder/rendering failure.
- Sleep/wake pauses and restarts the startup watchdog instead of consuming its timeout in the background.
- A no-frame timeout is no longer mislabeled as a server connection failure.
- Status diagnostics now expose startup network bytes and the last playback failure.

## Included

- Plex Home profile switcher, including protected-user PIN entry.
- Secure endpoint identity and profile-token verification before a server route is saved.
- Cached Home, library, and poster data; five-minute Home refresh; no full-library reload after playback.
- Paged large-library loading, Collections and Unwatched views.
- Ranked search with All, Movies, Shows, and Episodes filters.
- Preferred H.264 1080p version selection plus an explicit version picker with codec, bitrate, and file size.
- Per-profile, per-title/show memory for media version, audio track, and subtitle track.
- Direct Play, 720p compatible transcode, and 480p safe transcode paths.
- Plex playback session identifiers, progress reporting, and transcode-session cleanup.
- Configurable seek buttons and coalesced hardware/D-pad seeking.
- Skip Intro/Credits modes: Off, on-screen button, or automatic.
- Next-episode autoplay with configurable 0/5/10/15/30-second countdown.
- Wi-Fi/network retry, app resume refresh, native audio focus, and in-place playback retry.
- Watched badges, Continue Watching refresh, and memory-pressure poster cleanup.
- Redacted diagnostics for endpoint, profile, selected version, content startup, first-frame time, decoder, and video format.

## Verified off-car

- Flutter static analysis: clean.
- Flutter tests: 19 passed, including 800×480 and 1280×720 coverage.
- Android unit tests: passed.
- Native Kotlin/ExoPlayer compilation: passed.
- APK manifest: version 1.2.5 (11), minimum API 19, target API 34.
- APK native ABI: armeabi-v7a only.
- APK signatures: v1 and v2 verified.
- APK SHA-256: `f76d12bc0bff39eb81e46ed7a5386bcb5b15c9928d3cf8f256483af6a7c330a6`.

## One-pass M5 check

1. Install over 1.1.0 and confirm the existing account remains signed in.
2. Switch Plex Home profiles once, including a PIN-protected profile if available.
3. Open a multi-version title, choose a subtitle, and confirm that subtitle appears immediately during playback.
4. Tap the video to show the large controls; test Play/Pause, rewind, forward, the seek bar, Audio switching, CC Off/On, and Close.
5. Direct Play a local-copy H.264 1080p title, use D-pad seek repeatedly, sleep/wake the unit, and resume.
6. Direct Play a Zurg-backed title and leave it playing for 2–3 minutes; if Direct Play cannot render it, confirm the automatic 720p/480p fallback can start.
7. Play one 720p-compatible transcode and one 480p-safe transcode.
8. Verify Skip Intro/Credits and the Play Next countdown on an episode that has Plex markers.
9. Reopen the title and confirm its version/audio/subtitle choices were remembered.
10. Open Status and photograph both columns if anything fails; include the startup network-byte and last-failure rows.

Physical ECARX/M5 playback remains the final hardware gate because its Android 4.4 decoder and vehicle firmware cannot be reproduced by desktop tests.

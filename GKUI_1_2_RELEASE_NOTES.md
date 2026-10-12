# Plezy GKUI 1.2.13 — GitHub Connection Fix (unreleased)

This is the consolidated API 19 / ARMv7 release for the ECARX XE1115H head unit. Phone remote and mirroring are intentionally excluded.

## 1.2.13 GitHub connection fix

- In-app updates no longer fail with an SSL handshake error. Android 4.4 supports the AES-GCM cipher suites that GitHub and other current servers require, but only enables them by default from Android 4.4W (API 20), so the head unit offered only older CBC suites and GitHub ended the handshake. Every secure connection the app makes now offers the forward-secret AES-GCM and ChaCha20 suites first, keeping the older ones as a fallback.
- In-app updates trust GitHub's newer Sectigo certificates. GitHub serves github.com and api.github.com from either Let's Encrypt or Sectigo's Public Server Authentication hierarchy; Android 4.4 predates the Sectigo roots, so an update check or download could fail whenever GitHub answered with a Sectigo certificate. The app now bundles Sectigo Public Server Authentication Root R46 and E46 and their USERTrust RSA and ECC cross-signers, next to the Let's Encrypt and DigiCert roots it already carried.

## 1.2.12 car-sized controls

- The details screen fits the 800x480 screen without scrolling: a large Back button, the poster, the summary scrolling in place, large Version, Audio and Subtitles buttons that show the current choice, and one large Play or Resume button with Start over beside it. The 720p and 480p modes moved behind a quality button, since Plezy already falls back to them by itself.
- The player controls are larger: Close, title, Audio and CC along the top, big round rewind, play and forward buttons in the middle, and the seek bar with times along the bottom. Buttons light up when pressed.
- Tapping the video now shows or hides the controls; before, taps on the picture were ignored. The controls hide five seconds after the video starts or the last touch, stay up while paused, seeking or choosing tracks, and come back when playback pauses.
- A title or show that only plays in 720p or 480p remembers it: Play and the next autoplayed episode start in that mode instead of failing direct play first. The quality button shows and changes it.
- Starting a title asks Plex for its details and checks its file in one request. Automatic retries of a file that was just playing skip the file check.
- The player uses the chosen file's own length, so a different cut of a film is no longer mistaken for a stream that stopped early.
- Resume points are saved on the head unit, so a crash or a dead connection keeps the position until Plex records a later view.
- When a video stops with an error, Home shows why, how many reconnects were tried, and a Resume button.
- Settings has a connection test that shows the route (local, remote or relay), the response time and the address, and switches to a working address when the saved one fails.
- The Status screen can show the latest redacted logs as a QR code to scan with a phone.
- The side navigation no longer cuts off Status on the 480-pixel screen, and its buttons fill the rail's height.
- Error messages from the network read as one short sentence instead of a paragraph of developer text.
- A reconnect interrupted by the head unit sleeping keeps the rest of its wait when it wakes.
- Screen tests keep 800x480 pictures of the main screens to catch layout regressions.

## 1.2.11 playback and profile fixes

- Cached Home, sections and library pages are identified by server and Plex Home profile. Responses from before a profile change or sign-out cannot overwrite the current cache. Older unscoped caches refresh from Plex once after upgrading; sign-in and playback settings remain saved.
- Playback pauses whenever the player leaves the foreground, including while buffering or reconnecting. Sleep/wake preserves the intention to play, while a manual pause stays paused. Pending reconnects wait until the player resumes and are cancelled when it closes.
- Audio and subtitles use explicit current-track selections first, then remembered title/show choices, configured language preferences and Plex defaults. Remembered choices survive new track IDs on the next episode; Details and its track pickers display the same resolved selection as playback.
- Cached library startup restores the next-page offset and Load more state, keeping titles beyond the first page accessible.
- The optional missing-file check has a 1.5-second total startup budget. Progress reports and transcode cleanup have two-second total budgets, run independently of recovery/autoplay and cancel stalled requests.
- External subtitle URLs must keep the verified Plex origin (scheme, host and port) and cannot contain embedded user credentials. The native player also checks the subtitle origin before attaching authenticated requests.
- Skip Intro/Credits markers that arrive after playback starts are delivered to that running video. Session matching prevents old marker responses from affecting the next episode, and markers arriving before the native activity opens are queued for it.
- Play from beginning reports zero to Plex from the first progress update, instead of the saved resume position.
- Regression coverage includes stale profile and sign-out responses, pagination, language precedence, startup/telemetry budgets, subtitle origins, start-over progress, delayed marker delivery and native sleep/wake behavior.

## 1.2.10 connection recovery

- Titles whose video file is missing on the Plex server now show "Video file missing" instead of closing the app. Plezy asks Plex whether the file exists before opening the player, and a 404 from the server is reported the same way without trying the 720p/480p fallbacks.
- An unexpected error inside the player now ends playback with an error message instead of returning to the launcher. If the app does crash, the Status screen shows the last crash (code locations only, no addresses or tokens).
- If the saved Plex address stops answering (for example the home Wi-Fi address once the car is on 4G), Plezy looks up the server's addresses again and switches to one that works, instead of failing every request.
- Server addresses are now tested all at once, so an unreachable home address no longer adds about 12 seconds per attempt; a Plex relay is used only when no direct address answers.
- When a refresh fails, saved Home and library content stays on screen with an "Offline" notice; pull down to retry. Only a rejected Plex token returns to the sign-in screen.
- A metadata or connection error before the player opens no longer runs the 720p/480p fallback ladder; those fallbacks are kept for real playback failures.
- Closing the player while it shows "Reconnecting to Plex" closes it, instead of reopening the video.
- A car switching between day and night mode no longer restarts the player.
- Remembered audio/subtitle choices keep the most recently played titles when the 200-title limit is reached.
- The updater picks the newest stable GKUI release from the release list (the XGIMI build shares the repository), keeps working if the GitHub account is renamed, and deletes the downloaded APK once it is installed.
- Cached Home and library data now lives in files instead of Android shared preferences, so settings changes and the 5-minute Home refresh no longer rewrite hundreds of KB on the head unit. The cache from 1.2.9 is moved over automatically.
- The native player and updater share one TLS setup and connection pool instead of rebuilding the certificate store for every video.
- The update check runs again when the head unit wakes up (at most every 12 hours), not only when the app starts.
- Diagnostics also hide tokens written as JSON, Bearer values and passwords in addresses. The privacy policy now describes exactly what Plezy GKUI stores and contacts.
- Pull-request and branch CI builds are signed with a throwaway key; only the release job uses the car's certificate, and it now runs the formatting check and Android unit tests before publishing.

## 1.2.9 start over and in-app updates

- A resumable title now shows both **Resume from hh:mm** and **Play from beginning**. The latter explicitly starts at zero and does not reuse the saved Plex position.
- Plezy checks the latest stable `plezy-gkui` GitHub release automatically after startup; Settings also has a large **Check now** action.
- Updates download directly on the head unit, removing the USB-transfer step. Android still shows its required installer confirmation.
- The updater accepts only the expected API 19 ARMv7 asset from this repository, checks the GitHub SHA-256, package ID, version, and installed signing certificate before opening it.
- Android 8+ units are directed to the per-app unknown-sources permission when necessary; the ECARX Android 4.4 unit uses its existing system unknown-sources setting.

## 1.2.8 steadier Zurg streams

- The player buffers up to 50 seconds ahead (about 21 MiB on this head unit, a third of the app heap) instead of 18 seconds / 12 MiB, so short Zurg read pauses no longer stall the picture.
- After a stall, playback waits for 6 seconds of video instead of 2.5 before continuing, which stops the play-stop-play stutter on a slow mount.
- A failed read is retried quietly up to 10 times with growing gaps (about 40 seconds in all) before the player gives up; Plex server errors (5xx, 408, 429) are retried too, while missing files and permission errors still fail at once.
- If the player still loses the stream, it reconnects up to 3 times (after 2, 4 and 8 seconds) and shows "Reconnecting to Plex" on screen. A pause of more than 3 seconds mid-video shows "Waiting for the server…".
- A stream cut off more than a minute before the end is resumed instead of being treated as finished, so it no longer marks the video watched or jumps to the next episode.
- If a playing video still fails, the app reopens it once automatically from where it stopped. Retry and the 720p/480p fallbacks also continue from that point instead of the original start position.
- Details screens now say "Resume from 12:34", add a start-over action, and update their progress after you return from the player. Episodes show their season and episode number, and details show the runtime.
- Steering-wheel Play, Pause, Stop, Next and Previous keys work in the player (Next/Previous seek).

## 1.2.7 subtitles on by default

- Subtitles are on by default: a title without a remembered choice uses Plex's selected subtitle, or the first available one when Plex has none. Turning CC Off is still remembered for that title or show.
- A title without a remembered audio choice uses Plex's default audio track again instead of the first one.
- New releases are built, signed with the 1.2.5 certificate, checked and published automatically when a new version is merged.

## 1.2.6 car controls and track memory

- Fixes the large GKUI player controls falling back to the stock controller on API 19: the seek bar set `ProgressBar.setMinHeight`, which only exists from API 29. This call, not `setAllCaps` or start/end margins, is the likely cause of the 1.2.4 `NoSuchMethodError`.
- Release builds now fail on any framework call newer than API 19 (Android Lint `NewApi` is fatal), and a GKUI CI workflow builds the API 19 APK, runs lint, and runs the Flutter and Android tests on every push and pull request.
- Audio and subtitle choices made inside the player are now remembered, and are reused by the 720p/480p fallback, Retry, and the next episode.
- A show-level audio or subtitle choice now carries to other episodes by language, since Plex stream IDs differ per episode.
- The CC and Audio buttons show what ExoPlayer actually selected, so CC no longer reads Off while subtitles are showing.
- Network reconnects reset after 30 seconds of steady playback, so each mobile-data dropout gets two fresh retries instead of two per video.
- Same-language audio or subtitle tracks are matched by container order when labels are missing.
- Track titles and container positions are retained across episodes, keeping commentary and Simplified/Traditional Chinese choices distinct when they share a language code.
- The Audio and CC pickers no longer crash the player if the track list changes while they are open.
- Reconnect retries reset only after 30 seconds of actual continuous playback, not while paused.

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
- Automatic signed in-app updates from the official Plezy GKUI GitHub release.

## Verified off-car

- Flutter static analysis and all 65 GKUI Flutter tests pass.
- All 36 Android unit tests, Kotlin/ExoPlayer compilation, and fatal API-19 `NewApi` lint pass.
- The release APK is version 1.2.11 (17), minimum API 19, target API 34, and ARMv7 only.
- APK v1/v2 signatures, certificate continuity, manifest, ABI, and SHA-256 are verified before publishing; the checksum is recorded on the GitHub release.

## One-pass M5 check

1. Install over 1.1.0 and confirm the existing account remains signed in.
2. Switch Plex Home profiles once, including a PIN-protected profile if available.
3. Open a multi-version title, choose a subtitle, and confirm that subtitle appears immediately during playback.
4. Tap the video to show the large controls; test Play/Pause, rewind, forward, the seek bar, Audio switching, CC Off/On, and Close.
5. Direct Play a local-copy H.264 1080p title, use D-pad seek repeatedly, sleep/wake the unit, and resume.
6. Direct Play a Zurg-backed title and leave it playing for 2–3 minutes; if Direct Play cannot render it, confirm the automatic 720p/480p fallback can start.
7. Play one 720p-compatible transcode and one 480p-safe transcode.
8. Verify Skip Intro/Credits and the Play Next countdown on an episode that has Plex markers.
9. Reopen a partly watched title; test both Resume and Play from beginning.
10. In Settings, tap Check now. On 1.2.11 it should report current; use this path for the next release instead of USB.
11. After upgrading, let the first online refresh rebuild the scoped content cache. Reopen the app and check Load more in a library with more than one page.
12. While a video is buffering or reconnecting, press Pause or put the unit to sleep. Confirm it stays paused in the background and follows your previous play/pause choice after waking.
11. Open Status and photograph both columns if anything fails; include the startup network-byte and last-failure rows.

Physical ECARX/M5 playback remains the final hardware gate because its Android 4.4 decoder and vehicle firmware cannot be reproduced by desktop tests.

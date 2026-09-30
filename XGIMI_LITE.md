# Plezy XGIMI Lite

Plezy XGIMI Lite is a Chinese-first, low-memory Android TV distribution of Plezy for a 1080p family projector. The initial base is the pinned upstream `2.22.0` release. The profile is generic and can be used on other constrained Android TV devices; no behavior is keyed to the XGIMI manufacturer string.

## Target hardware

- Android TV 12 / API 31
- ARMv8 CPU and Mali-G52 GPU
- 1920×1080 at 60 Hz
- Approximately 1.8 GiB usable system RAM
- Projector speakers, without an AVR
- Wi-Fi 5 on a 300 Mbps internet connection

## Build profile

Build with `--dart-define=FAMILY_PROJECTOR_MODE=true`. The profile seeds defaults only when a setting has no saved value, so each choice remains user-overridable:

- Simplified Chinese UI
- reduced visual effects
- comfortable library density and normal card spacing
- full TV cards, hero artwork retained, and Explore hidden
- ambient lighting and audio passthrough disabled
- stereo audio channel limit
- automatic memory-aware playback buffer
- Chinese subtitle search language
- Direct Play for a source already covered by the selected quality

Artwork remains sharp. Upstream 2.22.0 already caps reduced-tier artwork downloads at three concurrent requests, uses a 64 MiB Flutter image cache, caps the Skia cache, requests server-sized artwork, and avoids disk-side image re-decoding. XGIMI Lite preserves those mechanisms.

## Playback policy

- mpv remains the initial Android default because that is the 2.22.0 default. ExoPlayer remains available in advanced playback settings. The best backend is not considered settled until both are tested on the projector.
- Direct Play is preferred. The profile does not impose a 6–8 Mbps cap and does not penalize a compatible 10–30 Mbps 1080p file.
- When Plex exposes multiple versions and no user/version preference is active, the profile selects an existing playable 720p–1080p source, strongly favoring 1080p SDR over 4K HDR or Dolby Vision. It does not create a transcode.
- If no display-sized HD version exists, upstream selection is retained.
- Playback buffering remains on Plezy's memory-aware automatic tier.
- Projector-speaker playback defaults to stereo downmix and no passthrough.

Strictly refusing all video transcoding is not enabled in test 1. Direct Play selection is improved, but an incompatible single-version source can still reach Plezy's normal fallback. A hard refusal needs real-device codec results and a localized failure path so it does not strand family users without an explanation.

## Chinese subtitles

Explicit manual choices and server-selected tracks remain authoritative. When no such choice exists, Family Projector Mode ranks available text tracks as:

1. Simplified Chinese (`zh-CN`, `zh-SG`, `zh-Hans`)
2. Traditional Chinese (`zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant`)
3. Generic Chinese (`zh`, `zho`, `chi`)
4. English
5. Off

`简`, `繁`, `CHS`, `CHT`, `SC`, and `TC` title hints are used only when language metadata is absent or generic. Proper language metadata wins over filename/title text. Manual subtitle search remains available.

## Diagnostics

Open **Settings → Advanced → View logs**. Its header now reports:

- Android version and API level
- supported ABIs and current process ABI
- total and available RAM
- render surface and refresh rate
- effects tier and image display budget
- H.264, HEVC, VP9, and AV1 decoder components
- hardware/software and secure-decoder classification
- advertised maximum width/height and profiles
- whether the Family Projector profile is active

The existing performance overlay continues to expose live playback information. No Plex token is added to the diagnostic payload.

## Build outputs

`.github/workflows/xgimi-lite.yml` builds and uploads both `arm64-v8a` and `armeabi-v7a` APKs plus tarballs. Both variants should be retained until the projector confirms its Android userspace ABI.

Test builds use an ephemeral test-only signing key so they can be sideloaded without repository secrets. The key is deleted before artifact packaging. Installations from different CI runs may require uninstalling the previous test build first; production/update-compatible builds need a stable protected signing secret.

## Known limitations

- Real XGIMI measurements are still required for mpv versus ExoPlayer, dropped frames, seek latency, HEVC Main10, complex ASS rendering, and long-play memory stability.
- GPU model is not reported by the Android framework diagnostics yet.
- Source preference applies only when Plex exposes multiple existing versions and no explicit version choice overrides it.
- The family defaults are a compile-time distribution profile rather than a one-tap runtime preset in the standard Plezy build.

<h1>
  <img src="assets/plezy.png" alt="Plezy logo" height="24" />
  Plezy XGIMI Lite
</h1>

A performance-focused Android TV build of [Plezy](https://github.com/edde746/plezy) for low-memory 1080p projectors. It is based on Plezy **2.22.0** and tuned first for an XGIMI projector with Android TV 12, about 1.8 GiB of usable RAM, a Mali-G52 GPU, and built-in stereo speakers.

This branch is intentionally separate from **Plezy GKUI**. GKUI is a compact API 19 client using native ExoPlayer; XGIMI Lite keeps the complete Plezy 2.22 interface and mpv/FFmpeg playback stack.

> **Test release:** the APKs are installable, CI-verified, and signed with a permanent XGIMI Lite key, but playback still needs validation on the physical projector.

## Download

Download the APKs from [Plezy XGIMI Lite 2.22.0 Test 4](https://github.com/jialim/plezy-gkui/releases/tag/xgimi-lite-v2.22.0-test4).

| APK | Use it when |
| --- | --- |
| `arm64-v8a` | Try this first on modern XGIMI Android TV projectors. |
| `armeabi-v7a` | Use this only if Android rejects the ARM64 APK or diagnostics show a 32-bit userspace. |

Both APKs contain exactly one native ABI. Release assets also include compressed `.tar.gz` copies for easier transfer; extract the APK before sideloading.

### Installation

1. Download the appropriate APK from Releases.
2. Allow installation from unknown sources for your file manager or ADB.
3. Install the APK and complete Plex, Jellyfin, or Emby sign-in.
4. Open **Settings → Advanced → View logs** and save the diagnostics header before testing playback.

Test 4 establishes the permanent signing identity for XGIMI Lite. Future releases signed with this key can update Test 4 in place while preserving sign-in and settings. Tests 1-3 used unrelated disposable keys; uninstall one of those legacy tests before installing Test 4. If you have not installed an earlier test, install Test 4 directly.

## Projector-focused defaults

The `FAMILY_PROJECTOR_MODE` build profile seeds settings only when the user has not already chosen a value:

- Simplified Chinese interface and Chinese subtitle search
- reduced visual effects and memory-aware buffering
- comfortable TV card density with D-pad navigation
- Explore and ambient lighting disabled
- audio passthrough disabled and stereo output selected
- Direct Play preferred without an arbitrary bitrate ceiling
- existing playable 1080p SDR versions preferred over 4K HDR/Dolby Vision versions
- 1.2× ten-foot UI scale so 40 px controls render at least 48 px on a 1080p surface
- high-contrast white text, distinct charcoal cards, and a thick amber focus ring

Manual settings, explicit media-version choices, and server-selected tracks remain authoritative.

The projector palette keeps a black background for dark-room viewing but avoids near-black cards that disappear on a low-contrast projection surface. Amber focus is reinforced by a 4 px outline and a larger focused-state scale, so navigation does not rely on colour alone.

## Chinese subtitle priority

When no manual or server choice exists, text subtitles are ranked as:

1. Simplified Chinese (`zh-CN`, `zh-SG`, `zh-Hans`)
2. Traditional Chinese (`zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant`)
3. Generic Chinese (`zh`, `zho`, `chi`)
4. English
5. Off

`简`, `繁`, `CHS`, `CHT`, `SC`, and `TC` title hints are consulted only when proper language metadata is absent or generic.

## Diagnostics

Open **Settings → Advanced → View logs** to see:

- Android version, API level, supported ABIs, and process ABI
- total and available RAM
- render resolution and refresh rate
- H.264, HEVC, VP9, and AV1 decoder inventory
- hardware/software and secure-decoder classification
- maximum advertised resolution and codec profiles, including HEVC Main/Main10
- whether Family Projector Mode is active

The diagnostics do not include a Plex token.

## APK size

The ARM APK is roughly 90–96 MB because full Plezy bundles the Flutter runtime, mpv, FFmpeg, libass, Cronet, broad CJK fonts, and related native libraries. The compressed release archive is about 48 MB. This is expected and is not caused by accidentally combining ARM32 and ARM64.

Plezy GKUI is much smaller because it is a separate lightweight client that relies on Android's ExoPlayer and device codecs rather than bundling the complete Plezy media stack.

## Known limitations

- mpv remains the initial backend; ExoPlayer is available in advanced playback settings. Real hardware testing will decide which should become the projector default.
- A compatible 1080p version is preferred when Plex exposes one, but a single incompatible source can still reach Plezy's normal transcode fallback.
- Strict refusal of all video transcoding is not enabled yet.
- HEVC Main10, complex ASS subtitles, seek latency, dropped frames, thermal behavior, and 30+ minute memory stability need device testing.
- The APKs are published as pre-releases until hardware validation is complete. Test 4 and later use the protected permanent XGIMI Lite signing key.

See [XGIMI_LITE.md](XGIMI_LITE.md) for implementation details and [XGIMI_TESTING.md](XGIMI_TESTING.md) for the physical-device checklist.

## Build from source

Prerequisites: Flutter 3.47.1 and Java 21.

```bash
flutter pub get --enforce-lockfile --no-example
flutter test test/media/media_version_family_projector_test.dart test/services/family_projector_subtitle_test.dart --dart-define=FAMILY_PROJECTOR_MODE=true
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64 \
  --dart-define=FAMILY_PROJECTOR_MODE=true \
  '--dart-define=FAMILY_PROJECTOR_NAME=Plezy XGIMI Lite'
```

Unsigned local release builds are not suitable for sideloading. Branch releases require the protected XGIMI signing secrets; CI refuses to publish if they are missing. Pull-request checks may use an isolated temporary key. Key material is deleted before artifact upload.

## Upstream and license

Plezy XGIMI Lite is an unofficial device-focused distribution maintained in this fork. General Plezy development, platform downloads, and project documentation live at [edde746/plezy](https://github.com/edde746/plezy).

Licensed under [GPL-3.0](LICENSE). Playback is powered by Plezy's mpv/FFmpeg stack and Android ExoPlayer.

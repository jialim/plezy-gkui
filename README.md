<h1>
  <img src="assets/plezy.png" alt="Plezy logo" height="24" />
  Plezy XGIMI Lite
</h1>

A performance-focused Android TV build of [Plezy](https://github.com/edde746/plezy) for low-memory 1080p projectors. It is based on Plezy **2.22.0** and tuned first for an XGIMI projector with Android TV 12, about 1.8 GiB of usable RAM, a Mali-G52 GPU, and built-in stereo speakers.

This branch is intentionally separate from **Plezy GKUI**. GKUI is a compact API 19 client using native ExoPlayer; XGIMI Lite keeps the complete Plezy 2.22 interface and mpv/FFmpeg playback stack.

> **Test release:** the APKs are installable, CI-verified, and signed with a permanent XGIMI Lite key, but playback still needs validation on the physical projector.

## Download

Download the APKs from [Plezy XGIMI Lite 2.22.0 Test 8](https://github.com/jialim/plezy-gkui/releases/tag/xgimi-lite-v2.22.0-test8).

| APK | Use it when |
| --- | --- |
| `armeabi-v7a` | **Use this for our confirmed 32-bit XGIMI projector.** |
| `arm64-v8a` | For other devices with confirmed 64-bit userspace. |

Both APKs contain exactly one native ABI. Release assets also include compressed `.tar.gz` copies for easier transfer; extract the APK before sideloading.

### Installation

1. Download the appropriate APK from Releases.
2. Allow installation from unknown sources for your file manager or ADB.
3. Install the APK and complete Plex, Jellyfin, or Emby sign-in.
4. Open **Settings → Advanced → View logs** and save the diagnostics header before testing playback.

Test 7 introduced the permanent package ID `app.plezylite.xgimi`. Test 8 and later update Test 7 in place and preserve sign-in and settings. The permanent signing key established in Test 4 is unchanged.

If you are moving from Test 6 or earlier, this is a **one-time move to a separate app**. The new launcher entry is **Plezy XGIMI Lite**; the older app is called **Plezy**. You must sign in again. To keep your app preferences, use **Export Settings** in the old app and **Import Settings** in the new app. Server watch history remains on Plex/Jellyfin/Emby. Keep the old app until the new one is working; uninstalling it is optional and is not required to install XGIMI Lite. No further package-ID changes are planned.

### Updating without USB

From Test 6 onward, XGIMI Lite checks this repository's pre-releases and can download the APK that matches the installed ABI. Choose **Download and install** in the update prompt. Android still asks for confirmation; the first time, enable **Allow from this source** for Plezy and return to the app, which continues to the installer automatically. The APK is streamed to cache and its GitHub SHA-256 digest is verified before Android opens it.

Test 8 adds **Cancel**, a bounded download duration, separate connection/storage/verification messages, and checks against downgrades. Release version codes must increase before CI will publish. A cancelled or failed partial download is removed.

### Readability and subtitle memory

Choose **Settings → Appearance → Projector interface size**: Normal (1.2×), Large (1.4×), or Extra-large (1.6×). Controls update immediately, and the detail action row scrolls with D-pad focus when space is tight. Unfocused actions stay at 85% brightness.

Subtitle choices are remembered by viewer and show/movie, using language, title and subtitle type across episodes. **Settings → Playback → Reset remembered subtitles** clears only the current viewer's choices. Earlier unscoped Test 7 choices are not inherited because their owner cannot be identified; select a subtitle once to save it for your viewer.

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
- a visible **Play from beginning** action whenever the main button would resume partially watched media
- an in-app, integrity-checked updater for future XGIMI Lite releases

Manual settings, explicit media-version choices, and server-selected tracks remain authoritative.

### Compared with official Plezy

This fork is based directly on official **2.22.0** and retains its playback engine, supported backends and upstream playback fixes. The projector changes are mostly defaults and accessibility: larger controls, stronger focus contrast, Chinese subtitle memory, start-over and an APK updater. Reduced animations, stereo output, hidden Explore and preference for an available 1080p SDR version are adjustable; 4K/HDR and surround support are not removed. The full mpv/FFmpeg stack remains, so the v7a APK is still about 91 MB. Future official releases need to be merged into this fork before their new fixes are included.

The projector palette keeps a black background for dark-room viewing but avoids near-black cards that disappear on a low-contrast projection surface. Amber focus is reinforced by a 4 px outline and a larger focused-state scale, so navigation does not rely on colour alone.

## Chinese subtitle priority

When no manual or server choice exists, text subtitles are ranked as:

1. Simplified Chinese (`zh-CN`, `zh-SG`, `zh-Hans`)
2. Traditional Chinese (`zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant`)
3. Generic Chinese (`zh`, `zho`, `chi`)

Without a Chinese track, or when the audio is already Chinese, the projector default leaves subtitles off. Manual or server-selected English subtitles remain available.

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

# Plezy XGIMI Lite

Plezy XGIMI Lite is a Chinese-first, low-memory Android TV distribution of Plezy for a 1080p family projector. The initial base is the pinned upstream `2.22.0` release. The profile is generic and can be used on other constrained Android TV devices; no behavior is keyed to the XGIMI manufacturer string.

## Target hardware

- Android TV 12 / API 31
- ARMv8 CPU and Mali-G52 GPU
- Confirmed 32-bit Android userspace: install the `armeabi-v7a` APK
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
- 1.2× ten-foot UI scaling for a 1080p projector surface
- white primary text, brighter secondary text, distinct charcoal surfaces, and amber actions/focus

Artwork remains sharp. Upstream 2.22.0 already caps reduced-tier artwork downloads at three concurrent requests, uses a 64 MiB Flutter image cache, caps the Skia cache, requests server-sized artwork, and avoids disk-side image re-decoding. XGIMI Lite preserves those mechanisms.

The accessibility palette is tuned for an elderly viewer on a low-lumen projector in a dark room. A 4 px amber focus outline and larger focused-state scale remain visible even though the reduced-effects tier deliberately disables expensive blurred focus glows.

Test 8 offers Normal (1.2×), Large (1.4×), and Extra-large (1.6×) under Appearance. TV design-height calculations track the chosen root scale so they do not shrink the controls back down. Narrow detail action rows scroll as D-pad focus moves. Unfocused actions retain 85% brightness. Subtitle memory uses semantic intent and a canonical viewer scope; invalid cache shapes are discarded, and Playback settings can reset just the current viewer's choices. Unowned Test 7 entries are not inherited.

The UI scale multiplies Flutter's logical pixels, which Android TV usually reports at density 2.0 (960×540 logical on a 1080p panel), not 1:1. Normal therefore lays the UI out on about 800×450, Large on about 686×386 and Extra-large on 600×338. Check the projector's density on the Logs screen ("dpi") and smoke-test Large and Extra-large before recommending them.

Test 9 adds, for the remote and the sofa:

- The first launch asks 中文 or English before anything else, sign-in included. Settings > General switches it later and lists only Simplified Chinese, Traditional Chinese and English. Every screen now has Simplified and Traditional Chinese text; upstream had left about 40 strings (audio channels, library filters and others) in English, and the installer's error toast is Chinese.
- Back with the controls hidden or showing asks "press Back again to stop" for three seconds, so one stray press does not end a film.
- The remote's CC key cycles subtitles (Off included), its audio key cycles audio tracks, and Menu raises the player controls.
- New installs default to larger, bold subtitles (46 instead of 38) with a thicker outline. Existing custom subtitle settings are kept.
- Chinese subtitles no longer show empty boxes for less common characters such as 诶 and 谘. A companion subtitle font adds the ~9000 GBK, GB2312 and Big5 hanzi the bundled Go Noto font lacks (827 of GB2312 and 4941 of Big5 were missing). It adds about 3.4 MB to the APK.
- A full Chinese subtitle track is chosen over a forced, signs-only one. Cantonese audio still turns Chinese subtitles on; Mandarin audio does not.
- Scrolling back left along the detail action row works again; it only scrolled forward.
- Update downloads resume after a dropped connection instead of starting the 95 MB APK again, and the startup update prompt waits until the player closes.
- The Logs screen lists the display's supported modes, density and HDR types, so frame-rate matching can be judged before it is turned on.

Update downloads use abortable streaming requests, a Cancel action, stalled/overall timeouts, integrity checks, and separate network/storage/verification/installer errors. Release notes publish actual per-ABI Android version codes; both the updater and native verifier reject equal/older builds. CI requires an increasing build number and runs the Android JVM suite, including APK verifier tests, before building a release. The package ID remains `app.plezylite.xgimi` and the launcher label is now Plezy XGIMI Lite.

## Playback policy

- mpv remains the initial Android default because that is the 2.22.0 default. ExoPlayer remains available in advanced playback settings. The best backend is not considered settled until both are tested on the projector.
- Direct Play is preferred. The profile does not impose a 6–8 Mbps cap and does not penalize a compatible 10–30 Mbps 1080p file.
- When Plex exposes multiple versions and no user/version preference is active, the profile selects an existing playable 720p–1080p source, strongly favoring 1080p SDR over 4K HDR or Dolby Vision. It does not create a transcode.
- If no display-sized HD version exists, upstream selection is retained.
- Playback buffering remains on Plezy's memory-aware automatic tier.
- Projector-speaker playback defaults to stereo downmix and no passthrough.

Strictly refusing all video transcoding is not enabled in test 1. Direct Play selection is improved, but an incompatible single-version source can still reach Plezy's normal fallback. A hard refusal needs real-device codec results and a localized failure path so it does not strand family users without an explanation.

## Chinese subtitles

Chinese subtitles are on by default for movies and for shows, drama and anime alike: when nobody has chosen a subtitle, the profile turns one on if a Chinese track exists and the audio is not already Chinese. English-only or Chinese-audio titles keep subtitles off.

A subtitle someone picks in the player (a specific track, or Off) is remembered on the projector for that show or movie and reused for every later episode, across restarts, until someone picks again. Plex itself only remembers per episode file and stores Off the same way as "never chosen", so this local memory takes precedence over Plex's per-file selection. A track is carried to another episode by language and title, so Simplified/Traditional or commentary choices stay distinct.

When the profile picks a track itself, it ranks them as:

1. Simplified Chinese (`zh-CN`, `zh-SG`, `zh-Hans`, `chs`)
2. Traditional Chinese (`zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant`, `cht`)
3. Generic Chinese (`zh`, `zho`, `chi`, `cmn`, `yue`)

`简`/`簡`, `繁`, `CHS`, `CHT`, `SC`, `TC`, `GB`, `BIG5`, `Hans`, `Hant`, `Simplified`, and `Traditional` title hints split generic Chinese tracks, and are used for untagged tracks. Proper language metadata wins over filename/title text. Manual subtitle search remains available.

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

`.github/workflows/xgimi-lite.yml` builds and uploads both `arm64-v8a` and `armeabi-v7a` APKs plus tarballs. This projector uses `armeabi-v7a`; arm64 remains available for other devices with confirmed 64-bit userspace.

Every push to `plezy-xgimi-lite` that passes the checks is published as the next GitHub pre-release, `xgimi-lite-v<version>-test<N>`, with both APKs, the tarballs, their SHA-256 and the commits since the previous test release.

Branch releases are signed with the permanent key in the `XGIMI_KEYSTORE_BASE64`, `XGIMI_KEYSTORE_PASSWORD`, `XGIMI_KEY_ALIAS` and `XGIMI_KEY_PASSWORD` repository secrets. The certificate has remained unchanged since Test 4; Test 7 introduced the new package ID, and Test 7 onward update in place and keep sign-in and settings. Test 6 and earlier install the new package as a separate app once, without requiring uninstall. The release workflow fails closed when any signing secret is missing; only pull-request checks may fall back to a throwaway key. Tests 1-3 used unrelated disposable keys and cannot be updated in place to Test 4. Pull requests and tag pushes never receive the key, even from this repository, because their APK artifacts are public; they sign with a throwaway key. The key file is deleted before artifact packaging.

XGIMI Lite uses the package ID `app.plezylite.xgimi` (earlier test builds used upstream's `com.edde746.plezy`). Content-provider authorities derive from it, so it can be installed next to official Plezy. The build moving to the new ID installs as a separate app once; later builds update it in place. CI refuses to publish an APK with any other package ID.

Test 6 adds the XGIMI updater. It selects the newest `xgimi-lite-v<version>` or `xgimi-lite-v<version>-test<N>` release (a stable build sorts after the tests of the same version, and the version is read from `pubspec.yaml` by CI), chooses the APK for the running process ABI, streams it to the app cache, verifies the SHA-256 digest supplied by GitHub, checks that the APK is this app (`app.plezylite.xgimi`) signed with the installed certificate, and only then opens Android's package installer. Android's install confirmation remains mandatory. On first use Android may also require **Allow from this source**; returning to Plezy resumes the pending install automatically. The stable Test 4+ certificate is Android's final protection against an unrelated APK replacing the app.

Partially watched movies and episodes also expose a separate, labeled **Play from beginning** action in the projector detail screen. It sends an explicit zero start position through the normal playback path, leaving the ordinary Resume action and stored server progress intact.

To create the key once:

```sh
keytool -genkeypair -keystore xgimi.jks -alias xgimi -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Plezy XGIMI Lite'
base64 -w0 xgimi.jks   # paste into the XGIMI_KEYSTORE_BASE64 secret
```

## Upstream updates

XGIMI Lite is upstream Plezy 2.22.0 plus a small, mostly additive set of commits behind the `FAMILY_PROJECTOR_MODE` flag. As of 2026-10-11 there is no newer upstream release tag, but upstream `main` is 43 commits ahead with fixes that matter on this projector:

- Xvid/MPEG-4 and MPEG-2 playback on Android mpv, and an ffmpeg DNS wait that stalled stream opening for 18–30 seconds on some networks.
- Multi-part movies playing past Part 1, and slow servers no longer failing at the 10-second connect timeout.
- Plex Home profile switches no longer loading the previous user's rows.
- Dolby Vision played as its HDR10/HLG base layer, and subtitle position above 100 to move subtitles into the letterbox.

A trial merge of upstream `main` conflicts only in three generated translation files (regenerate with `dart run slang`) and `external_player_service.dart`. Merge the next upstream release tag as soon as it is published, while the divergence is this small, and keep new fork behaviour in `family_projector_profile.dart` rather than in shared upstream files.

## Known limitations

- Real XGIMI measurements are still required for mpv versus ExoPlayer, dropped frames, seek latency, HEVC Main10, complex ASS rendering, and long-play memory stability.
- GPU model is not reported by the Android framework diagnostics yet.
- Source preference applies only when Plex exposes multiple existing versions and no explicit version choice overrides it.
- The family defaults are a compile-time distribution profile rather than a one-tap runtime preset in the standard Plezy build.

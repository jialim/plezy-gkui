# XGIMI Lite physical test checklist

Record the APK filename, backend, and the diagnostics header from **Settings → Advanced → View logs** for each run.

## Install and browse

- [ ] Install `arm64-v8a`; if Android rejects it, install `armeabi-v7a`
- [ ] Launch without a crash or blank screen
- [ ] Complete Plex sign-in and select the expected Plex Home user
- [ ] Confirm the initial UI is Simplified Chinese
- [ ] Confirm the server, Home, Continue Watching, Recently Added, Movies, and TV Shows load
- [ ] Scroll several poster rows quickly; note missing, blurry, or late artwork
- [ ] Confirm approximately 4–5 comfortable cards across the 1080p screen
- [ ] Test Up/Down/Left/Right, OK, and Back in Home, grids, details, settings, and dialogs
- [ ] Confirm focus never disappears and the focus indication is obvious

## Playback

- [ ] Direct Play H.264 1080p SDR
- [ ] Direct Play HEVC 1080p SDR if diagnostics reports a hardware decoder
- [ ] Test HEVC Main10 only if the decoder profile list advertises Main10
- [ ] On an item with 4K HDR/DV and 1080p SDR versions, confirm the 1080p SDR version is selected
- [ ] Confirm a 10–30 Mbps compatible 1080p file is not rejected only for bitrate
- [ ] Confirm the playback overlay reports Direct Play or Direct Stream rather than video Transcode
- [ ] Test seek forward/back and resume from a saved position
- [ ] Play for at least 30 minutes and note dropped frames, A/V drift, or thermal slowdown
- [ ] Return Home and confirm navigation remains responsive

## Subtitles and audio

- [ ] With Simplified, Traditional, generic Chinese, and English tracks present, confirm Simplified Chinese is selected
- [ ] Remove Simplified Chinese and confirm Traditional Chinese is selected
- [ ] Confirm proper Plex language metadata beats misleading title/filename text
- [ ] Confirm manual subtitle selection and subtitle search remain usable
- [ ] Test SRT and a representative Chinese ASS subtitle
- [ ] Confirm projector-speaker audio is present and intelligible in stereo
- [ ] Confirm a lossless/multichannel source does not cause video transcoding solely for audio

## Backend comparison

- [ ] Repeat H.264, HEVC, seek, resume, and subtitle tests with mpv
- [ ] Repeat the same tests with ExoPlayer
- [ ] Record startup time, dropped frames, CPU/heat impression, memory, seek response, and subtitle correctness

## Memory snapshots

- [ ] Record available RAM immediately after launch
- [ ] Record it after browsing at least five rows and opening several details pages
- [ ] Record it 10 minutes into playback
- [ ] Record it after 30+ minutes of playback
- [ ] Record it after returning Home
- [ ] Note any Android process restart, black surface, artwork eviction storm, or progressive slowdown

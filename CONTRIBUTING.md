# Contributing

Plezy GKUI is an Android 4.4 (API 19), ARMv7 Plex client for GKUI head units.
Everything in this repository serves that one app.

## Layout

- `lib/main_gkui.dart` — app entry point and screens (`lib/main.dart` forwards
  to it, so plain `flutter run` works).
- `lib/gkui/` — Plex API client, content cache, diagnostics.
- `android/app/src/main/kotlin/` — native ExoPlayer player, updater and TLS.
- `test/gkui/` and `android/app/src/test/` — Flutter and JVM unit tests.
- `docs/` — porting plan, risk gates and historical build reports.

## Toolchain

Flutter 3.19.6 / Dart 3.3.4, JDK 17, Android SDK 34. Newer Flutter releases no
longer target API 19, so do not upgrade the pinned versions casually.

## Before you push

```sh
dart format lib test
flutter analyze
flutter test
cd android && ./gradlew :app:testDebugUnitTest
```

A release build (`flutter build apk --release --target-platform android-arm`)
runs Android lint with `NewApi` as a fatal error, so a framework call newer
than API 19 fails the build instead of crashing the head unit.

## Releases

Bump `version` in `pubspec.yaml`, add a section at the top of
`GKUI_1_2_RELEASE_NOTES.md` marked `(unreleased)`, and merge to
`gkui/api19-implementation`. The release workflow builds, verifies the signing
certificate and publishes `gkui-v<version>`; installed head units are then
offered the update in the app.

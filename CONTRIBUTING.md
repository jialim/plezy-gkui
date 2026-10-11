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

Flutter 3.19.6 / Dart 3.3.4, JDK 17, Android SDK 34.

These pins are permanent for this app, not overdue upgrades:

- **Flutter 3.19.6** is the last release whose engine runs on API 19.
  Flutter 3.22 raised the minimum to API 21.
- **ExoPlayer 2.19.1** is the final ExoPlayer 2 release. Its successor,
  AndroidX Media3, requires API 21 from 1.4, so Media3 1.3.x is the only
  newer player that could still run here. Moving to it is a package rename
  across the native player, worth doing only for a specific fix.
- **OkHttp 3.12.x** is the last OkHttp line for Android 4.4.

Dependency bumps that keep these floors are fine; anything that raises the
minimum SDK is not. Dependabot ignores major updates for this reason.

## Screen tests

`test/gkui/screen_golden_test.dart` keeps 800x480 pictures of the main
screens in `test/gkui/goldens/`. After an intended layout change, regenerate
them and review the images in the pull request:

```sh
flutter test --update-goldens test/gkui/screen_golden_test.dart
```

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

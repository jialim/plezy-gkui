# Privacy Policy for Plezy GKUI

**Last Updated: October 10, 2026**

Plezy GKUI ("the app") is an unofficial Plex client for GKUI in-car head
units. This policy describes what the app stores on the head unit and which
services it contacts. The app has no backend of its own: nothing is sent to
servers run by the Plezy GKUI developer.

## What the app stores on the head unit

All of the following stays in the app's private storage on the head unit and
is removed when you uninstall the app:

- **Plex sign-in tokens**: the Plex account token and the token for the
  selected Plex Media Server, plus the server's name, ID and address. They are
  kept in the app's Android shared preferences, which other apps cannot read.
  They are not encrypted, because Android 4.4 head units have no dependable
  hardware-backed key storage; anyone with root or debugging access to the head
  unit could read them. Signing out deletes them.
- **A random client identifier** that Plex uses to recognize this head unit.
- **Settings and remembered choices**: seek intervals, skip and autoplay
  settings, and the media version, audio track, subtitle and playback
  quality you chose per title or show (up to 200 titles).
- **Resume points**: where this head unit last stopped up to 100 titles, so a
  crash or a lost connection keeps the position. They belong to the current
  server and profile, and signing out or switching profile deletes them.
- **Cached Plex content**: Home shelves, library lists and poster images, so
  the app can start quickly and stay usable offline. Signing out or switching
  Plex Home profile clears the cached lists.
  Cached lists carry a server/profile identifier and a credential fingerprint
  so another account's content is not restored; the fingerprint is not a token
  and cannot authenticate to Plex.
- **Diagnostics**: a bounded in-memory log for the Status screen, and the last
  crash report (exception types and code locations only). Tokens, passwords
  and URL credentials are removed from log lines, and crash reports never
  contain messages or addresses.
- **Downloaded app updates**, until the update is installed.

Android backups are disabled for the app, so this data is not copied to a
backup.

## Services the app contacts

- **Plex** (`plex.tv`, `clients.plex.tv`): PIN sign-in, the list of your Plex
  Media Servers, and Plex Home profile switching. Plex's privacy policy
  applies: https://www.plex.tv/about/privacy-legal/
- **Your Plex Media Server**: library browsing, artwork, playback and playback
  progress, over HTTPS only.
- **GitHub** (`api.github.com`, `github.com`, GitHub's release-download hosts):
  the app checks this project's public release list for a newer Plezy GKUI
  version and, if you choose to install it, downloads the APK. GitHub sees the
  head unit's IP address and a `Plezy-GKUI/<version>` user agent. GitHub's
  privacy statement applies:
  https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement

The app does not use analytics, advertising or crash-reporting services, and
does not share your information with anyone else.

## Your choices

- **Sign out** in the app to delete the stored Plex tokens and cached content.
- **Uninstall the app** to delete everything it stored.
- Manage your Plex account and authorized devices at https://app.plex.tv.

## Changes to this policy

Changes are published in this file in the project repository, with the date
at the top updated.

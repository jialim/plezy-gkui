import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:plezy/utils/app_logger.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'base_shared_preferences_service.dart';
import 'device_performance.dart';
import 'family_projector_profile.dart';

enum XgimiUpdateFailure { network, storage, verification, installer, busy }

class XgimiUpdateException implements Exception {
  const XgimiUpdateException(this.failure, {this.cause});
  final XgimiUpdateFailure failure;
  final Object? cause;

  @override
  String toString() => 'XGIMI update ${failure.name}: ${cause ?? failure.name}';
}

class XgimiUpdateCancelled implements Exception {}

/// A transfer that stopped early; the next request resumes from its end.
class XgimiDownloadInterrupted implements Exception {
  const XgimiDownloadInterrupted(this.reason);
  final String reason;

  @override
  String toString() => 'XGIMI download interrupted: $reason';
}

class XgimiUpdateCancellation {
  final AbortController _abort = AbortController();
  void cancel() => _abort.abort();
  bool get isCancelled => _abort.isAborted;
  void throwIfCancelled() {
    if (isCancelled) throw XgimiUpdateCancelled();
  }
}

/// Service to check for new versions on GitHub
/// Only enabled when ENABLE_UPDATE_CHECK build flag is set
///
/// On macOS (non-Homebrew) and installed Windows: delegates to Sparkle/WinSparkle
/// via auto_updater for native update dialogs and in-app installs.
/// On all other platforms: falls back to GitHub API check + browser link dialog.
class UpdateService {
  static const String _githubRepo = 'edde746/plezy';
  static const String _xgimiGithubRepo = 'jialim/plezy-gkui';
  static const String _feedUrl = 'https://cdn.jsdelivr.net/gh/edde746/plezy@appcast/appcast.xml';

  /// `xgimi-lite-v<version>` or `xgimi-lite-v<version>-test<N>`. The version
  /// is parsed rather than pinned so installs keep finding releases after the
  /// fork moves to a newer upstream version or publishes a stable build.
  static final RegExp _xgimiTagPattern = RegExp(r'^xgimi-lite-v(\d+)\.(\d+)\.(\d+)(?:-test(\d+))?$');
  static const String _gitCommit = String.fromEnvironment('GIT_COMMIT');
  static const MethodChannel _xgimiInstallerChannel = MethodChannel('com.plezy/xgimi_update');
  static const int _maximumXgimiApkBytes = 160 * 1024 * 1024;
  static bool _xgimiDownloadActive = false;

  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';

  // Check cooldown: 6 hours
  static const Duration _checkCooldown = Duration(hours: 6);

  static bool _nativeUpdaterInitialized = false;

  /// Check if update checking is enabled via build flag
  static bool get isUpdateCheckEnabled {
    return FamilyProjectorProfile.enabled || const bool.fromEnvironment('ENABLE_UPDATE_CHECK', defaultValue: false);
  }

  static bool get _useXgimiUpdater => FamilyProjectorProfile.enabled && Platform.isAndroid;

  /// The running VM's own ABI (`... on "android_arm"` vs `"android_arm64"`),
  /// used when device diagnostics are not loaded yet. Guessing 64-bit would
  /// download an APK a 32-bit-only projector cannot install.
  static bool get _dartVmIs64Bit => Platform.version.contains('_arm64') || Platform.version.contains('_x64');

  /// Whether any in-app update path applies to this install.
  /// False inside a packaged (MSIX/Store) install: the Store owns updates and
  /// the package directory is read-only, so neither WinSparkle nor the GitHub
  /// fallback dialog has anything it can do. Gates the settings entry too, so
  /// no dead affordance ships.
  static bool get isUpdateCheckAvailable => isUpdateCheckEnabled && !PlatformDetector.isPackagedInstall();

  /// Whether the native auto_updater (Sparkle/WinSparkle) should be used.
  /// True on macOS (non-Homebrew) and installed Windows (has uninstaller).
  static bool get useNativeUpdater {
    if (!isUpdateCheckAvailable) return false;
    if (Platform.isMacOS) return !_isHomebrewInstall();
    if (Platform.isWindows) return _isInstalledApp() && !_isWingetInstall();
    return false;
  }

  /// Initialize the native auto_updater (Sparkle/WinSparkle).
  /// Call once at startup if [useNativeUpdater] is true.
  static Future<void> initNativeUpdater() async {
    if (_nativeUpdaterInitialized) return;

    try {
      await autoUpdater.setFeedURL(_feedUrl);
      _nativeUpdaterInitialized = true;
    } catch (error, stackTrace) {
      appLogger.e('Failed to initialize native auto updater', error: error, stackTrace: stackTrace);
    }
  }

  /// Trigger a background update check via Sparkle/WinSparkle.
  /// Only shows UI if an update is found.
  static Future<void> checkForUpdatesNative({bool inBackground = true}) async {
    if (!_nativeUpdaterInitialized) {
      await initNativeUpdater();
      if (!_nativeUpdaterInitialized) return;
    }
    try {
      await autoUpdater.checkForUpdates(inBackground: inBackground);
    } catch (error, stackTrace) {
      appLogger.e('Native update check failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Check if the macOS app was installed via Homebrew.
  /// Homebrew casks live under /opt/homebrew/Caskroom/ or /usr/local/Caskroom/.
  static bool _isHomebrewInstall() {
    final execPath = Platform.resolvedExecutable;
    return execPath.contains('/Caskroom/') || execPath.contains('/homebrew/');
  }

  /// Check if the Windows app was installed via winget.
  /// The Inno Setup installer writes a .winget marker file when invoked with /WINGET=1.
  static bool _isWingetInstall() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File('$exeDir\\.winget').existsSync();
  }

  /// Check if the Windows app is an installed copy (not portable).
  /// The Inno Setup installer places unins000.exe next to the executable.
  static bool _isInstalledApp() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File('$exeDir\\unins000.exe').existsSync();
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keySkippedVersion, version);
  }

  static Future<String?> getSkippedVersion() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    return prefs.getString(_keySkippedVersion);
  }

  /// Check if cooldown period has passed since last check
  static Future<bool> shouldCheckForUpdates() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final lastCheckString = prefs.getString(_keyLastCheckTime);
    if (lastCheckString == null) return true;

    final now = DateTime.now();
    final lastCheck = DateTime.tryParse(lastCheckString);
    if (lastCheck == null || lastCheck.isAfter(now)) {
      await prefs.remove(_keyLastCheckTime);
      return true;
    }

    return now.difference(lastCheck) >= _checkCooldown;
  }

  static Future<void> _updateLastCheckTime() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keyLastCheckTime, DateTime.now().toIso8601String());
  }

  /// Internal method that performs the actual update check
  /// [respectCooldown] - if true, checks cooldown and records the attempt before the request
  /// [throwOnFailure] - if true, a failed check (network, non-200, bad payload)
  /// is rethrown instead of reading as "no update"
  static Future<Map<String, dynamic>?> _performUpdateCheck({
    required bool respectCooldown,
    MediaServerHttpClient? client,
    bool forceEnabled = false,
    bool throwOnFailure = false,
  }) async {
    if (!forceEnabled && !isUpdateCheckAvailable) {
      return null;
    }

    // Check cooldown if requested
    if (respectCooldown && !await shouldCheckForUpdates()) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (respectCooldown) {
        await _updateLastCheckTime();
      }

      if (_useXgimiUpdater) {
        return await _performXgimiUpdateCheck(packageInfo: packageInfo, client: client ?? httpClient);
      }

      final response = await (client ?? httpClient).get(
        'https://api.github.com/repos/$_githubRepo/releases/latest',
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (response.statusCode != 200) {
        throw StateError('Release check returned HTTP ${response.statusCode}');
      }
      final data = response.data;
      final latestVersion = data['tag_name'] as String;

      // Remove 'v' prefix if present
      final cleanVersion = latestVersion.startsWith('v') ? latestVersion.substring(1) : latestVersion;

      final hasUpdate = _isNewerVersion(cleanVersion, currentVersion);

      if (hasUpdate) {
        // Check if this version was skipped
        final skippedVersion = await getSkippedVersion();
        if (skippedVersion == cleanVersion) {
          return null;
        }

        return {
          'hasUpdate': true,
          'currentVersion': currentVersion,
          'latestVersion': cleanVersion,
          'releaseUrl': data['html_url'] as String,
          'releaseName': data['name'] as String? ?? 'Version $cleanVersion',
          'releaseNotes': data['body'] as String? ?? '',
          'publishedAt': data['published_at'] as String,
        };
      }
    } catch (error, stackTrace) {
      appLogger.e('Failed to check for updates', error: error, stackTrace: stackTrace);
      if (throwOnFailure) rethrow;
    }

    return null;
  }

  static Future<Map<String, dynamic>?> _performXgimiUpdateCheck({
    required PackageInfo packageInfo,
    required MediaServerHttpClient client,
  }) async {
    // A local build has no trustworthy release identity. Release CI always
    // supplies GIT_COMMIT, which is also stored as target_commitish by the
    // publishing job.
    if (_gitCommit.isEmpty) return null;

    final response = await client.get(
      'https://api.github.com/repos/$_xgimiGithubRepo/releases?per_page=100',
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode != 200 || response.data is! List) {
      throw StateError('XGIMI release check returned HTTP ${response.statusCode}');
    }

    final selected = selectXgimiRelease(
      response.data as List<dynamic>,
      is64Bit: DevicePerformance.is64BitProcess ?? _dartVmIs64Bit,
    );
    if (selected == null) return null;

    final targetCommit = selected['targetCommit'] as String;
    if (targetCommit.toLowerCase() == _gitCommit.toLowerCase()) return null;
    if (selected['installVersionCode'] == null) {
      // CI writes one line per ABI; without it the build cannot be compared,
      // so it is skipped rather than risking a downgrade.
      appLogger.w('XGIMI release ${selected['tag']} has no version code for this ABI in its notes; skipped.');
      return null;
    }
    if (!isNewerXgimiRelease(selected, currentVersion: packageInfo.version, currentBuild: packageInfo.buildNumber)) {
      return null;
    }

    final tag = selected['tag'] as String;
    if (await getSkippedVersion() == tag) return null;

    final shortCommit = _gitCommit.substring(0, _gitCommit.length.clamp(0, 7));
    return {
      'hasUpdate': true,
      'currentVersion': '${packageInfo.version}+${packageInfo.buildNumber} ($shortCommit)',
      'latestVersion': selected['versionLabel'],
      'skipVersionKey': tag,
      'releaseUrl': selected['releaseUrl'],
      'releaseName': selected['releaseName'],
      'releaseNotes': selected['releaseNotes'],
      'publishedAt': selected['publishedAt'],
      'installUrl': selected['installUrl'],
      'installSha256': selected['installSha256'],
      'installFileName': selected['installFileName'],
      'installVersionCode': selected['installVersionCode'],
      'canInstall': true,
    };
  }

  @visibleForTesting
  static bool isNewerXgimiRelease(
    Map<String, dynamic> release, {
    required String currentVersion,
    required String currentBuild,
  }) {
    final code = release['installVersionCode'];
    final currentCode = int.tryParse(currentBuild);
    if (code is! int || currentCode == null || code <= currentCode) return false;
    final version = release['version'] as String?;
    return version != null && (version == currentVersion || _isNewerVersion(version, currentVersion));
  }

  /// Select the newest usable XGIMI test release and the APK matching this
  /// app process. Kept pure so release payload edge cases are unit-testable.
  @visibleForTesting
  static Map<String, dynamic>? selectXgimiRelease(List<dynamic> releases, {required bool is64Bit}) {
    final candidates = <({List<int> order, int? number, String version, Map<String, dynamic> release})>[];
    for (final raw in releases) {
      if (raw is! Map) continue;
      final release = Map<String, dynamic>.from(raw);
      if (release['draft'] == true) continue;
      final tag = release['tag_name'];
      final match = tag is String ? _xgimiTagPattern.firstMatch(tag) : null;
      if (match == null) continue;
      final parts = [for (var group = 1; group <= 3; group++) int.parse(match.group(group)!)];
      final number = match.group(4) == null ? null : int.parse(match.group(4)!);
      // A stable build of a version sorts after every test build of it.
      final order = [...parts, number == null ? 1 : 0, number ?? 0];
      candidates.add((order: order, number: number, version: parts.join('.'), release: release));
    }
    int compareOrder(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return 0;
    }

    candidates.sort((a, b) => compareOrder(b.order, a.order));

    final abiSuffix = is64Bit ? '-arm64-v8a.apk' : '-armeabi-v7a.apk';
    for (final candidate in candidates) {
      final release = candidate.release;
      final assets = release['assets'];
      if (assets is! List) continue;
      Map<String, dynamic>? asset;
      for (final rawAsset in assets) {
        if (rawAsset is! Map) continue;
        final value = Map<String, dynamic>.from(rawAsset);
        if (value['name'] is String && (value['name'] as String).endsWith(abiSuffix)) {
          asset = value;
          break;
        }
      }
      final installUrl = asset?['browser_download_url'];
      final digest = asset?['digest'];
      final targetCommit = release['target_commitish'];
      if (installUrl is! String ||
          digest is! String ||
          !digest.startsWith('sha256:') ||
          targetCommit is! String ||
          targetCommit.isEmpty) {
        continue;
      }
      // Releases are stable from build 10; the tag's -testN is only the counter.
      final label = candidate.number == null ? candidate.version : '${candidate.version} build ${candidate.number}';
      final notes = release['body'] is String ? release['body'] as String : '';
      final codeMatch = RegExp(
        '^\\s*- ${is64Bit ? 'arm64' : 'armv7'} APK version code:\\s*(\\d+)\\s*\$',
        multiLine: true,
      ).firstMatch(notes);
      return {
        'version': candidate.version,
        'installVersionCode': int.tryParse(codeMatch?.group(1) ?? ''),
        'testNumber': candidate.number,
        'versionLabel': label,
        'tag': release['tag_name'],
        'targetCommit': targetCommit,
        'releaseUrl': release['html_url'],
        'releaseName': release['name'] ?? 'Plezy XGIMI Lite $label',
        'releaseNotes': release['body'] ?? '',
        'publishedAt': release['published_at'] ?? '',
        'installUrl': installUrl,
        'installSha256': digest.substring('sha256:'.length).toLowerCase(),
        'installFileName': asset!['name'],
      };
    }
    return null;
  }

  /// Download, hash-check and open the Android package installer for an
  /// XGIMI release. The download streams to cache so a ~96 MB APK is never
  /// held in RAM on the projector.
  static Future<String> downloadAndInstallXgimiUpdate(
    Map<String, dynamic> updateInfo, {
    ValueChanged<double?>? onProgress,
    XgimiUpdateCancellation? cancellation,
  }) async {
    if (!_useXgimiUpdater || updateInfo['canInstall'] != true) {
      throw StateError('In-app APK installation is unavailable for this build.');
    }
    return _downloadAndInstallXgimiUpdate(updateInfo, onProgress: onProgress, cancellation: cancellation);
  }

  @visibleForTesting
  static Future<String> debugDownloadAndInstallXgimiUpdate(
    Map<String, dynamic> updateInfo, {
    required http.Client client,
    required Directory directory,
    XgimiUpdateCancellation? cancellation,
    ValueChanged<double?>? onProgress,
  }) => _downloadAndInstallXgimiUpdate(
    updateInfo,
    client: client,
    directory: directory,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  static Future<String> _downloadAndInstallXgimiUpdate(
    Map<String, dynamic> updateInfo, {
    http.Client? client,
    Directory? directory,
    XgimiUpdateCancellation? cancellation,
    ValueChanged<double?>? onProgress,
  }) async {
    if (_xgimiDownloadActive) throw const XgimiUpdateException(XgimiUpdateFailure.busy);
    final token = cancellation ?? XgimiUpdateCancellation();
    token.throwIfCancelled();
    _xgimiDownloadActive = true;
    var timedOut = false;
    final deadline = Timer(const Duration(minutes: 20), () {
      timedOut = true;
      token.cancel();
    });
    File? partialFile;
    // A network failure keeps the partial file for the next attempt to resume.
    var keepPartial = false;
    try {
      final url = Uri.parse(updateInfo['installUrl'] as String);
      final expectedSha256 = (updateInfo['installSha256'] as String).toLowerCase();
      final fileName = p.basename(updateInfo['installFileName'] as String);
      if (url.scheme != 'https' || url.host != 'github.com') {
        throw const FormatException('Invalid XGIMI release download URL.');
      }
      if (!fileName.endsWith('.apk') || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
        throw const FormatException('Invalid XGIMI release asset metadata.');
      }

      final downloadDirectory = directory ?? await getTemporaryDirectory();
      final finalFile = File(p.join(downloadDirectory.path, fileName));
      // Named by the expected digest, so an interrupted download of this
      // exact APK resumes and a partial of any other build is removed.
      final partialName = '$fileName.${expectedSha256.substring(0, 16)}.partial';
      partialFile = File(p.join(downloadDirectory.path, partialName));
      await removeStaleXgimiDownloads(downloadDirectory, keep: partialName);

      for (var attempt = 1; ; attempt++) {
        try {
          await _downloadXgimiRange(client ?? httpClient.inner, url, partialFile, token, onProgress);
          break;
        } catch (error) {
          if (token.isCancelled || attempt >= _xgimiDownloadAttempts || !isResumableDownloadError(error)) {
            keepPartial = !token.isCancelled && isResumableDownloadError(error);
            rethrow;
          }
          appLogger.w('XGIMI update download interrupted; resuming (attempt ${attempt + 1})', error: error);
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          token.throwIfCancelled();
        }
      }

      final actualDigest = (await sha256.bind(partialFile.openRead()).first).toString().toLowerCase();
      if (actualDigest != expectedSha256) {
        await partialFile.delete();
        throw const XgimiUpdateException(XgimiUpdateFailure.verification);
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partialFile.rename(finalFile.path);

      token.throwIfCancelled();
      deadline.cancel();
      final result = await _xgimiInstallerChannel.invokeMethod<String>('installApk', {'path': finalFile.path});
      if (result != 'installer_started' && result != 'permission_requested') {
        throw const XgimiUpdateException(XgimiUpdateFailure.installer);
      }
      return result!;
    } on PlatformException catch (error) {
      throw XgimiUpdateException(
        error.code == 'UPDATE_REJECTED' ? XgimiUpdateFailure.verification : XgimiUpdateFailure.installer,
        cause: error.message ?? error.code,
      );
    } on FileSystemException catch (error) {
      if (token.isCancelled && !timedOut) throw XgimiUpdateCancelled();
      throw XgimiUpdateException(XgimiUpdateFailure.storage, cause: error);
    } on FormatException {
      throw const XgimiUpdateException(XgimiUpdateFailure.verification);
    } on XgimiUpdateException {
      rethrow;
    } catch (error) {
      if (token.isCancelled && !timedOut) throw XgimiUpdateCancelled();
      if (error is MissingPluginException) throw const XgimiUpdateException(XgimiUpdateFailure.installer);
      if (timedOut) keepPartial = true;
      throw XgimiUpdateException(XgimiUpdateFailure.network, cause: error);
    } finally {
      deadline.cancel();
      token.cancel();
      try {
        if (partialFile != null && !keepPartial && await partialFile.exists()) {
          try {
            await partialFile.delete();
          } on FileSystemException {
            // A failed cleanup is retried before the next download.
          }
        }
      } finally {
        _xgimiDownloadActive = false;
      }
    }
  }

  static const int _xgimiDownloadAttempts = 3;

  /// Waits, checking every [poll], until [busy] is false. Used to hold the
  /// startup update prompt until playback ends.
  static Future<void> waitWhile(bool Function() busy, {Duration poll = const Duration(seconds: 15)}) async {
    while (busy()) {
      await Future<void>.delayed(poll);
    }
  }

  /// Failures a later request can continue from: a dropped or stalled
  /// connection, or a transfer that ended before the expected size.
  @visibleForTesting
  static bool isResumableDownloadError(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      error is HttpException ||
      error is XgimiDownloadInterrupted ||
      (error is http.ClientException && error is! http.RequestAbortedException);

  /// Downloads the rest of [partialFile], asking the server for only the
  /// bytes it does not have yet. A server that ignores the range sends the
  /// whole file, which then replaces the partial one.
  static Future<void> _downloadXgimiRange(
    http.Client client,
    Uri url,
    File partialFile,
    XgimiUpdateCancellation token,
    ValueChanged<double?>? onProgress,
  ) async {
    var existing = await partialFile.exists() ? await partialFile.length() : 0;
    if (existing >= _maximumXgimiApkBytes) {
      await partialFile.delete();
      existing = 0;
    }
    final request = http.AbortableRequest('GET', url, abortTrigger: token._abort.trigger)
      ..headers['Accept'] = 'application/vnd.android.package-archive';
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
    final response = await client.send(request).timeout(const Duration(seconds: 30));

    final int offset;
    final contentRange = response.headers['content-range'] ?? '';
    if (existing > 0 && response.statusCode == 206 && contentRange.startsWith('bytes $existing-')) {
      offset = existing;
    } else if (response.statusCode == 200) {
      offset = 0;
    } else if (existing > 0 && response.statusCode == 416) {
      // The partial file does not match what the server has; start over.
      await response.stream.drain<void>();
      await partialFile.delete();
      throw const XgimiDownloadInterrupted('range not satisfiable');
    } else {
      await response.stream.drain<void>().catchError((_) {});
      throw StateError('APK download returned HTTP ${response.statusCode}');
    }
    final remaining = response.contentLength;
    final total = remaining == null ? null : offset + remaining;
    if (total != null && (total <= 0 || total > _maximumXgimiApkBytes)) {
      throw StateError('APK download size is outside the allowed range.');
    }

    var received = offset;
    final sink = partialFile.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    try {
      await sink.addStream(
        response.stream.timeout(const Duration(seconds: 45)).map((chunk) {
          token.throwIfCancelled();
          received += chunk.length;
          if (received > _maximumXgimiApkBytes) {
            throw StateError('APK download exceeded the allowed size.');
          }
          onProgress?.call(total == null || total == 0 ? null : received / total);
          return chunk;
        }),
      );
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total != null && received != total) {
      throw XgimiDownloadInterrupted('received $received of $total bytes');
    }
  }

  /// Each update APK is ~95 MB and named per build, so earlier downloads would
  /// otherwise pile up in the projector's cache. [keep] names the partial
  /// download being resumed.
  @visibleForTesting
  static Future<void> removeStaleXgimiDownloads(Directory directory, {String? keep}) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      final name = p.basename(entry.path);
      if (entry is File &&
          name != keep &&
          name.startsWith('plezy-xgimi-lite-') &&
          (name.endsWith('.apk') || name.endsWith('.apk.partial'))) {
        try {
          await entry.delete();
        } on FileSystemException {
          // A file Android's installer still holds open is removed next time.
        }
      }
    }
  }

  @visibleForTesting
  static Future<Map<String, dynamic>?> debugPerformUpdateCheck({
    required bool respectCooldown,
    required MediaServerHttpClient client,
    bool throwOnFailure = false,
  }) {
    return _performUpdateCheck(
      respectCooldown: respectCooldown,
      client: client,
      forceEnabled: true,
      throwOnFailure: throwOnFailure,
    );
  }

  /// Check for updates on GitHub (manual check, ignores cooldown)
  /// Returns a map with update info, or null when there is no update (or the
  /// release is skipped). Throws when the check itself fails, so the caller
  /// can say so instead of reporting the latest version.
  static Future<Map<String, dynamic>?> checkForUpdates() {
    return _performUpdateCheck(respectCooldown: false, throwOnFailure: true);
  }

  /// Check for updates on startup (respects cooldown and skipped versions)
  /// Returns update info if available, null otherwise
  static Future<Map<String, dynamic>?> checkForUpdatesOnStartup() {
    return _performUpdateCheck(respectCooldown: true);
  }

  /// Parse version string into list of integers
  /// Handles versions like "1.2.3+4" by taking only the numeric parts
  static List<int> _parseVersionParts(String version) {
    return version.split('.').map((p) {
      final numPart = p.split('+').first.split('-').first;
      return int.tryParse(numPart) ?? 0;
    }).toList();
  }

  /// Compare two version strings
  /// Returns true if newVersion is newer than currentVersion
  static bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = _parseVersionParts(newVersion);
      final currentParts = _parseVersionParts(currentVersion);

      // Compare each part
      final maxLength = newParts.length > currentParts.length ? newParts.length : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        final newPart = i < newParts.length ? newParts[i] : 0;
        final currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }

      return false;
    } catch (error, stackTrace) {
      appLogger.e('Error comparing versions', error: error, stackTrace: stackTrace);
      return false;
    }
  }
}

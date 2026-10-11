part of '../../main_gkui.dart';

class GkuiController extends ChangeNotifier {
  final RedactingLogStore logs = RedactingLogStore(capacity: 160);
  PlexApi? api;
  AppPhase phase = AppPhase.starting;
  String? error;
  PlexPin? pin;
  String? pendingAccountToken;
  List<PlexServerResource> servers = const <PlexServerResource>[];
  List<PlexShelf> shelves = const <PlexShelf>[];
  List<PlexSection> sections = const <PlexSection>[];
  List<PlexMedia> libraryItems = const <PlexMedia>[];
  List<PlexMedia> searchResults = const <PlexMedia>[];
  List<PlexHomeUser> homeUsers = const <PlexHomeUser>[];
  PlexSection? selectedSection;
  PlexHomeUser? currentHomeUser;
  LibraryView libraryView = LibraryView.all;
  SearchMediaFilter searchFilter = SearchMediaFilter.all;
  GkuiSettings settings = const GkuiSettings();
  String searchQuery = '';
  String? lastSelectedVersion;
  int? lastFirstFrameMs;
  int? lastContentLoadMs;
  String? lastDecoder;
  String? lastVideoFormat;
  int? lastStartupNetworkBytes;
  String? lastPlaybackFailure;
  GkuiUpdateInfo? updateInfo;
  String? updateError;
  bool checkingForUpdate = false;
  bool testingConnection = false;
  String? connectionReport;
  PlaybackProblem? lastPlaybackProblem;
  bool installingUpdate = false;
  // What this car last played, so screens opened before playback show the
  // new resume point instead of the one Plex returned when they loaded. It is
  // also saved, so a crash or a dead connection keeps the position.
  Map<String, LocalProgress> _localProgress = <String, LocalProgress>{};
  bool loadingContent = false;
  bool searching = false;
  bool loadingMoreLibrary = false;
  bool libraryHasMore = false;
  int libraryNextStart = 0;
  bool switchingProfile = false;
  int authGeneration = 0;
  int contentGeneration = 0;
  int searchGeneration = 0;
  Timer? periodicRefresh;
  bool disposed = false;

  bool get clockValid => DateTime.now().year >= 2024;

  LocalProgress? _localFor(PlexMedia media) {
    final local = _localProgress[media.ratingKey];
    return local != null && local.supersedes(media) ? local : null;
  }

  int resumeOffsetFor(PlexMedia media) =>
      _localFor(media)?.positionMs ?? media.viewOffsetMs;

  bool isWatched(PlexMedia media) =>
      media.watched || _localFor(media)?.watched == true;

  void _clearLocalProgress() {
    _localProgress = <String, LocalProgress>{};
  }

  void _loadLocalProgress() {
    _localProgress = api?.loadLocalProgress() ?? <String, LocalProgress>{};
  }

  Future<void> initialize() async {
    logs.add('Starting consolidated GKUI build.');
    if (!clockValid) {
      logs.add('Clock is invalid; secure network access is paused.');
      phase = AppPhase.signedOut;
      notifySafely();
      return;
    }
    try {
      api ??= await PlexApi.create(logs);
      settings = api!.loadSettings();
      if (api!.session == null) {
        phase = AppPhase.signedOut;
      } else {
        _loadLocalProgress();
        shelves = api!.loadCachedHome();
        sections = api!.loadCachedSections();
        selectedSection = sections.isEmpty ? null : sections.first;
        final cachedPage = selectedSection == null
            ? null
            : api!.loadCachedSectionPage(selectedSection!.key);
        libraryItems = cachedPage?.items ?? const <PlexMedia>[];
        libraryNextStart = cachedPage?.nextStart ?? 0;
        libraryHasMore = cachedPage?.hasMore ?? false;
        if (shelves.isNotEmpty || sections.isNotEmpty) {
          phase = AppPhase.ready;
          logs.add('Showing cached Plex content while refreshing.');
          notifySafely();
        }
        await refreshContent(includeLibrary: libraryItems.isEmpty);
      }
    } catch (caught) {
      fail('Startup failed', caught);
    }
    notifySafely();
  }

  Future<void> retryClock() async {
    if (!clockValid) {
      error =
          'The head-unit date is still ${DateTime.now().year}. Connect Wi-Fi/4G or correct its clock.';
      notifySafely();
      return;
    }
    phase = AppPhase.starting;
    error = null;
    notifySafely();
    await initialize();
  }

  Future<void> beginSignIn() async {
    if (!clockValid) return retryClock();
    final generation = ++authGeneration;
    try {
      api ??= await PlexApi.create(logs);
      error = null;
      pin = await api!.createPin();
      phase = AppPhase.signingIn;
      notifySafely();
      for (var attempt = 0; attempt < 120; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (generation != authGeneration || disposed) return;
        final token = await api!.checkPin(pin!);
        if (token == null || token.isEmpty) continue;
        pendingAccountToken = token;
        logs.add('Plex sign-in approved.');
        servers = await api!.fetchServers(token);
        if (servers.isEmpty) {
          throw StateError(
              'No Plex Media Server with a secure HTTPS address was found.');
        }
        if (servers.length == 1) {
          await connectServer(token, servers.first);
        } else {
          phase = AppPhase.chooseServer;
          notifySafely();
        }
        return;
      }
      throw TimeoutException('Plex sign-in timed out.');
    } catch (caught) {
      if (generation == authGeneration) fail('Sign-in failed', caught);
    }
  }

  Future<void> connectServer(String token, PlexServerResource server) async {
    try {
      phase = AppPhase.starting;
      notifySafely();
      await api!.connect(token, server);
      pendingAccountToken = null;
      await refreshContent();
    } catch (caught) {
      fail('Server connection failed', caught);
    }
  }

  Future<void> chooseServer(PlexServerResource server) async {
    final token = pendingAccountToken;
    if (token == null) {
      fail('Server selection failed',
          StateError('The sign-in token is no longer available.'));
      return;
    }
    await connectServer(token, server);
  }

  Future<void> refreshContent({bool includeLibrary = true}) async {
    if (api?.session == null) return;
    final started = Stopwatch()..start();
    final generation = ++contentGeneration;
    loadingMoreLibrary = false;
    loadingContent = true;
    error = null;
    notifySafely();
    try {
      List<dynamic> results;
      try {
        results = await Future.wait<dynamic>(<Future<dynamic>>[
          api!.loadHome(),
          api!.loadSections(),
        ]);
      } catch (caught) {
        // The saved address may be the home LAN while the car is on 4G, so
        // pick a working route once before treating the server as down.
        if (!PlexApi.isUnreachable(caught)) rethrow;
        await api!.reconnect();
        if (generation != contentGeneration || disposed) return;
        results = await Future.wait<dynamic>(<Future<dynamic>>[
          api!.loadHome(),
          api!.loadSections(),
        ]);
      }
      if (generation != contentGeneration || disposed) return;
      shelves = results[0] as List<PlexShelf>;
      sections = results[1] as List<PlexSection>;
      final previousKey = selectedSection?.key;
      selectedSection = sections.cast<PlexSection?>().firstWhere(
            (section) => section?.key == previousKey,
            orElse: () => sections.isEmpty ? null : sections.first,
          );
      if (includeLibrary && selectedSection != null) {
        final page = await api!.loadSectionPage(selectedSection!.key);
        if (generation != contentGeneration || disposed) return;
        libraryItems = page.items;
        libraryNextStart = page.nextStart;
        libraryHasMore = page.hasMore;
        libraryView = LibraryView.all;
      }
      phase = AppPhase.ready;
      lastContentLoadMs = started.elapsedMilliseconds;
      logs.add('Plex content is ready.');
      unawaited(loadHomeUsers());
      _ensurePeriodicRefresh();
    } catch (caught) {
      if (generation == contentGeneration && !disposed) {
        if (keepsCachedContent(
            hasContent: shelves.isNotEmpty || sections.isNotEmpty,
            error: caught)) {
          // Keep the cached library browsable; Home shows the banner and
          // pull-to-refresh retries. Only a rejected token needs sign-in.
          error = message('Offline: showing saved Plex content', caught);
          logs.add(error!);
          phase = AppPhase.ready;
          _ensurePeriodicRefresh();
        } else {
          fail('Could not load Plex content', caught);
        }
      }
    } finally {
      if (generation == contentGeneration && !disposed) {
        loadingContent = false;
        notifySafely();
      }
    }
  }

  Future<void> selectSection(PlexSection section) async {
    final generation = ++contentGeneration;
    loadingMoreLibrary = false;
    selectedSection = section;
    loadingContent = true;
    error = null;
    notifySafely();
    try {
      libraryView = LibraryView.all;
      final page = await api!.loadSectionPage(section.key);
      if (generation != contentGeneration || disposed) return;
      libraryItems = page.items;
      libraryNextStart = page.nextStart;
      libraryHasMore = page.hasMore;
    } catch (caught) {
      if (generation == contentGeneration && !disposed) {
        error = message('Library failed to load', caught);
      }
    } finally {
      if (generation == contentGeneration && !disposed) {
        loadingContent = false;
        notifySafely();
      }
    }
  }

  Future<void> selectLibraryView(LibraryView view) async {
    final section = selectedSection;
    if (section == null) return;
    final generation = ++contentGeneration;
    loadingMoreLibrary = false;
    libraryView = view;
    loadingContent = true;
    error = null;
    notifySafely();
    try {
      if (view == LibraryView.collections) {
        final items = await api!.loadCollections(section.key);
        if (generation != contentGeneration || disposed) return;
        libraryItems = items;
        libraryHasMore = false;
        libraryNextStart = items.length;
      } else {
        final page = await api!.loadSectionPage(section.key,
            unwatchedOnly: view == LibraryView.unwatched);
        if (generation != contentGeneration || disposed) return;
        libraryItems = page.items;
        libraryNextStart = page.nextStart;
        libraryHasMore = page.hasMore;
      }
    } catch (caught) {
      if (generation == contentGeneration && !disposed) {
        error = message('Library view failed to load', caught);
      }
    } finally {
      if (generation == contentGeneration && !disposed) {
        loadingContent = false;
        notifySafely();
      }
    }
  }

  Future<void> loadMoreLibrary() async {
    final section = selectedSection;
    if (section == null ||
        libraryView == LibraryView.collections ||
        !libraryHasMore ||
        loadingMoreLibrary) return;
    final generation = contentGeneration;
    loadingMoreLibrary = true;
    notifySafely();
    try {
      final page = await api!.loadSectionPage(
        section.key,
        start: libraryNextStart,
        unwatchedOnly: libraryView == LibraryView.unwatched,
      );
      if (generation != contentGeneration || disposed) return;
      final known = libraryItems.map((item) => item.ratingKey).toSet();
      libraryItems = <PlexMedia>[
        ...libraryItems,
        ...page.items.where((item) => known.add(item.ratingKey)),
      ];
      libraryNextStart = page.nextStart;
      libraryHasMore = page.hasMore;
    } catch (caught) {
      if (generation == contentGeneration && !disposed) {
        error = message('More library items failed to load', caught);
      }
    } finally {
      if (generation == contentGeneration && !disposed) {
        loadingMoreLibrary = false;
        notifySafely();
      }
    }
  }

  Future<void> runSearch(String query) async {
    final generation = ++searchGeneration;
    searchQuery = query.trim();
    if (searchQuery.length < 2) {
      searching = false;
      searchResults = const <PlexMedia>[];
      notifySafely();
      return;
    }
    searching = true;
    error = null;
    notifySafely();
    try {
      final results = await api!.search(searchQuery, filter: searchFilter);
      if (generation != searchGeneration || disposed) return;
      searchResults = results;
    } catch (caught) {
      if (generation == searchGeneration && !disposed) {
        error = message('Search failed', caught);
      }
    } finally {
      if (generation == searchGeneration && !disposed) {
        searching = false;
        notifySafely();
      }
    }
  }

  Future<void> setSearchFilter(SearchMediaFilter value) async {
    searchFilter = value;
    if (searchQuery.length >= 2) {
      await runSearch(searchQuery);
    } else {
      notifySafely();
    }
  }

  Future<void> updateSettings(GkuiSettings value) async {
    settings = value;
    await api!.saveSettings(value);
    notifySafely();
  }

  Future<GkuiUpdateInfo?> checkForAppUpdate({bool silent = false}) async {
    if (checkingForUpdate || installingUpdate || !clockValid) return null;
    checkingForUpdate = true;
    updateError = null;
    notifySafely();
    try {
      final raw = await nativeChannel
          .invokeMapMethod<Object?, Object?>('checkForAppUpdate');
      if (raw == null) throw StateError('The updater returned no status.');
      updateInfo = GkuiUpdateInfo.fromMap(raw);
      logs.add(updateInfo!.available
          ? 'Update available: Plezy GKUI ${updateInfo!.latestVersion}.'
          : 'Update check: this GKUI build is current.');
      return updateInfo;
    } on PlatformException catch (caught) {
      updateError =
          caught.message ?? 'The update check failed (${caught.code}).';
      if (!silent) logs.add('Update check failed: $updateError');
      return null;
    } catch (caught) {
      updateError = compact(caught);
      if (!silent) logs.add('Update check failed: $updateError');
      return null;
    } finally {
      checkingForUpdate = false;
      notifySafely();
    }
  }

  Future<void> downloadAndInstallUpdate() async {
    if (installingUpdate) return;
    installingUpdate = true;
    updateError = null;
    notifySafely();
    try {
      final raw = await nativeChannel
          .invokeMapMethod<Object?, Object?>('downloadAndInstallUpdate');
      if (raw?['installerOpened'] != true) {
        throw StateError('No newer signed GKUI update is available.');
      }
      logs.add('Verified update downloaded; Android installer opened.');
    } on PlatformException catch (caught) {
      updateError =
          caught.message ?? 'Update installation failed (${caught.code}).';
      logs.add('Update installation failed: $updateError');
      rethrow;
    } catch (caught) {
      updateError = compact(caught);
      logs.add('Update installation failed: $updateError');
      rethrow;
    } finally {
      installingUpdate = false;
      notifySafely();
    }
  }

  Future<void> loadHomeUsers() async {
    try {
      homeUsers = await api!.loadHomeUsers();
      final saved = api!.currentHomeUserUuid;
      currentHomeUser = homeUsers.cast<PlexHomeUser?>().firstWhere(
            (user) => user?.uuid == saved,
            orElse: () => homeUsers.cast<PlexHomeUser?>().firstWhere(
                  (user) => user?.admin == true,
                  orElse: () => homeUsers.isEmpty ? null : homeUsers.first,
                ),
          );
      notifySafely();
    } catch (caught) {
      logs.add('Plex Home profiles unavailable: ${compact(caught)}');
    }
  }

  Future<void> switchProfile(PlexHomeUser user, {String? pin}) async {
    if (user.uuid == currentHomeUser?.uuid) return;
    switchingProfile = true;
    contentGeneration++;
    searchGeneration++;
    error = null;
    notifySafely();
    try {
      final token = await api!.switchHomeUser(user, pin: pin);
      final resources = await api!.fetchServers(token);
      if (resources.isEmpty) {
        throw StateError('This profile has no accessible Plex server.');
      }
      final currentServerId = api!.session?.serverId;
      final server = resources.firstWhere(
        (candidate) => candidate.id == currentServerId,
        orElse: () => resources.first,
      );
      await api!.connect(token, server);
      await api!.saveCurrentHomeUser(user);
      await api!.clearContentCache();
      currentHomeUser = user;
      _clearLocalProgress();
      shelves = const <PlexShelf>[];
      libraryItems = const <PlexMedia>[];
      searchResults = const <PlexMedia>[];
      await refreshContent();
      logs.add('Switched Plex Home profile to ${user.displayName}.');
    } catch (caught) {
      error = message('Profile switch failed', caught);
      rethrow;
    } finally {
      switchingProfile = false;
      notifySafely();
    }
  }

  Future<void> reconnectAfterResume() async {
    if (phase != AppPhase.ready || api?.session == null || loadingContent)
      return;
    logs.add('App resumed; refreshing Plex connection.');
    await refreshContent(includeLibrary: false);
  }

  void _ensurePeriodicRefresh() {
    periodicRefresh ??=
        Timer.periodic(const Duration(minutes: 5), (Timer timer) {
      if (phase == AppPhase.ready && !loadingContent && !switchingProfile) {
        unawaited(refreshHomeQuietly());
      }
    });
  }

  Future<void> refreshHomeQuietly() async {
    if (api?.session == null) return;
    final generation = contentGeneration;
    try {
      final updated = await api!.loadHome();
      if (generation != contentGeneration || disposed) return;
      shelves = updated;
      notifySafely();
    } catch (caught) {
      logs.add('Background Home refresh skipped: ${compact(caught)}');
    }
  }

  void handleMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    logs.add('Low-memory signal: released decoded artwork.');
  }

  Future<void> signOut() async {
    authGeneration++;
    contentGeneration++;
    searchGeneration++;
    periodicRefresh?.cancel();
    periodicRefresh = null;
    await api?.signOut();
    _clearLocalProgress();
    shelves = const <PlexShelf>[];
    sections = const <PlexSection>[];
    libraryItems = const <PlexMedia>[];
    phase = AppPhase.signedOut;
    error = null;
    notifySafely();
  }

  void cancelSignIn() {
    authGeneration++;
    pin = null;
    phase = AppPhase.signedOut;
    error = null;
    notifySafely();
  }

  void _updateLocalProgress(String ratingKey, int position,
      {bool watched = false}) {
    final progress = LocalProgress(
      positionMs: position,
      savedAtSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      watched: watched || _localProgress[ratingKey]?.watched == true,
    );
    _localProgress[ratingKey] = progress;
    unawaited(api?.saveLocalProgress(ratingKey, progress));
    PlexMedia update(PlexMedia item) => item.ratingKey == ratingKey
        ? item.copyWith(viewOffsetMs: position)
        : item;
    shelves = shelves
        .map((shelf) => PlexShelf(
            title: shelf.title, items: shelf.items.map(update).toList()))
        .toList();
    libraryItems = libraryItems.map(update).toList();
    searchResults = searchResults.map(update).toList();
  }

  /// The Settings connection test: times the saved address and finds
  /// another route when it does not answer.
  Future<void> testConnection() async {
    if (api?.session == null || testingConnection) return;
    testingConnection = true;
    connectionReport = null;
    notifySafely();
    try {
      final check = await api!.checkConnection();
      connectionReport = check.describe();
      logs.add('Connection test: ${check.describe().replaceAll('\n', ' / ')}');
      if (check.switched) unawaited(refreshContent(includeLibrary: false));
    } catch (caught) {
      connectionReport = message('No route reached the server', caught);
    } finally {
      testingConnection = false;
      notifySafely();
    }
  }

  void dismissPlaybackProblem() {
    lastPlaybackProblem = null;
    notifySafely();
  }

  void fail(String prefix, Object value) {
    error = message(prefix, value);
    logs.add(error!);
    phase = AppPhase.error;
    notifySafely();
  }

  String message(String prefix, Object value) {
    if (value is DioException && value.response?.statusCode == 401) {
      return '$prefix: Plex rejected the account or server token (HTTP 401).';
    }
    if (value is DioException && !clockValid) {
      return '$prefix: secure HTTPS cannot work while the car clock is incorrect.';
    }
    return '$prefix: ${compact(value)}';
  }

  /// One short line for the driver. Dio's own messages run to a paragraph
  /// of developer advice that does not fit a head-unit dialog.
  static String compact(Object value) {
    if (value is DioException) {
      final status = value.response?.statusCode;
      return switch (value.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The Plex server did not answer in time.',
        DioExceptionType.connectionError =>
          'The Plex server could not be reached.',
        DioExceptionType.badCertificate =>
          'The Plex server\'s certificate was not trusted.',
        DioExceptionType.cancel => 'The request was cancelled.',
        DioExceptionType.badResponse => status == null
            ? 'The Plex server sent an unexpected answer.'
            : 'The Plex server answered HTTP $status.',
        DioExceptionType.unknown => value.error == null
            ? 'The Plex server could not be reached.'
            : compact(value.error!),
      };
    }
    return value
        .toString()
        .replaceFirst(RegExp(r'^(Exception|StateError):\s*'), '');
  }

  void notifySafely() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    authGeneration++;
    contentGeneration++;
    searchGeneration++;
    periodicRefresh?.cancel();
    logs.dispose();
    super.dispose();
  }
}

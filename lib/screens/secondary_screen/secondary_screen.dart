import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../l10n/app_locale.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/services/secondary_apps_service.dart';
import 'package:video_player/video_player.dart';
import '../../models/config_model.dart';
import '../../models/secondary_achievement_item.dart';
import '../../models/secondary_display_state.dart';
import '../../models/retro_achievement_comment.dart';
import '../../repositories/retro_achievements_repository.dart';
import '../../services/retro_achievements_service.dart';
import '../../utils/no_glow_scroll_behavior.dart';
import 'background_builders.dart';
import 'now_playing_helpers.dart';
import 'widgets/achievement_comments.dart';
import 'widgets/achievement_panel.dart';
import 'widgets/app_dock.dart';
import 'widgets/now_playing_panel.dart';

class SecondaryScreen extends StatefulWidget {
  const SecondaryScreen({super.key});

  @override
  State<SecondaryScreen> createState() => _SecondaryScreenState();
}

class _SecondaryScreenState extends State<SecondaryScreen> {
  SecondaryDisplayState? _secondaryDisplayState;
  VideoPlayerController? _videoController;

  /// Latches true the first time the main engine reports `appReady`; drives the
  /// app dock's one-shot slide-up. Local so the oscillating shared-state flag
  /// can't un-reveal the dock. See [_buildDockOverlay].
  bool _dockRevealed = false;

  /// A BuildContext captured from *under* this screen's MaterialApp (and its
  /// Localizations). The _buildXxx helpers below run as methods on this State,
  /// so a bare `context` resolves to `this.context` — which sits ABOVE the
  /// MaterialApp and has no Localizations, making AppLocale.getString() return
  /// `<key> not found` on the secondary display. getString() calls use
  /// `_l10nContext ?? context` so they resolve against this instead.
  BuildContext? _l10nContext;
  Timer? _videoTimer;
  bool _showVideo = false;
  String? _currentVideoPath;

  /// Bumped every time the preview is torn down. [_initializeVideo] captures it
  /// on entry and re-checks after each await, so an in-flight init that started
  /// just as a game launched (which calls [_stopVideo]) throws away the
  /// controller it created instead of leaving it playing audio over the game.
  int _videoGeneration = 0;
  int _lastMediaRevision = 0;

  /// Auto-clearing timer for the "newly earned this session" celebration.
  Timer? _celebrationTimer;
  bool _celebrate = false;
  String? _celebrationKey;

  /// Whether the achievement panel renders the list view (vs the badge grid).
  /// Toggled by touch on the secondary screen; local to this engine.
  bool _achievementListView = false;

  /// Which page of the in-game container is showing: 0 = Now Playing,
  /// 1 = RetroAchievements. Local to this engine, flipped by the edge chevrons;
  /// resets to 0 on each new launch.
  int _inGamePanelPage = 0;
  SecondaryAchievementItem? _selectedAchievement;
  final Map<int, AchievementCommentsState> _commentsCache = {};
  int _commentsRequestGeneration = 0;
  bool _wasNowPlayingActive = false;
  String? _panelGameId;

  /// Ticks once a second while a game is active so the Now Playing "PLAY TIME"
  /// stat counts up live. [_sessionWatch] measures the current session, which is
  /// added to the DB-supplied total at render time.
  Timer? _playTimeTicker;
  final Stopwatch _sessionWatch = Stopwatch();

  /// Dims the in-game container after a spell of no activity, to cut glare and
  /// burn-in while playing. Any activity — launch, page flip, a new unlock, or a
  /// touch — wakes it to full brightness and restarts the countdown.
  Timer? _dimTimer;
  bool _inGameDimmed = false;

  /// Dock slot index currently being assigned via the app picker, or null when
  /// the picker is not open for slot assignment.
  int? _pickerSlot;

  /// True while the picker is open as a full app launcher (tap launches the
  /// app) rather than to assign a dock slot. Mutually exclusive with a
  /// non-null [_pickerSlot].
  bool _launcherOpen = false;

  /// Whether the app picker overlay is currently visible in either mode.
  bool get _pickerVisible => _pickerSlot != null || _launcherOpen;

  /// Whether the "enable Screen Return" explainer dialog is showing. Raised
  /// when the launcher is tapped while the accessibility service is off.
  bool _accessDialogVisible = false;

  /// Installed-app list backing the picker; null until first loaded.
  List<Map<String, dynamic>>? _pickerApps;
  bool _loadingPickerApps = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
      _secondaryDisplayState!.addListener(_onStateChanged);
      // Signal that the secondary screen is active — but only after the initial
      // state sync. Pushing it while the synced value is still null makes
      // updateState fall back to the WELCOME default and clobber the real
      // retained display state, which then shows until the next push.
      _signalSecondaryActiveWhenSynced();
    }
  }

  /// Marks the secondary display active once [SecondaryDisplayState] has pulled
  /// its initial value, so the flag layers onto the real state rather than the
  /// WELCOME placeholder.
  Future<void> _signalSecondaryActiveWhenSynced() async {
    final state = _secondaryDisplayState;
    if (state == null) return;
    // A null value means no cached state was restored synchronously; in that
    // case initialSync is assigned and safe to await. A non-null value means the
    // state is already in hand.
    if (state.value == null) {
      await state.initialSync;
    }
    if (!mounted) return;
    state.updateState(isSecondaryActive: true);
  }

  void _onStateChanged() {
    final state = _secondaryDisplayState?.value;
    if (state == null) return;

    // A re-scrape rewrites the art at the same path, so this engine's image
    // cache still holds the old bitmap. When the producer bumps mediaRevision,
    // clear the cache so the rebuild (its ValueKey also carries the revision)
    // re-decodes the fresh bytes from disk. The secondary engine only ever
    // shows one game's art, so a full clear is cheap — and it correctly drops
    // the wheel's ResizeImage-wrapped entries, which a bare FileImage.evict
    // would miss.
    if (state.mediaRevision != _lastMediaRevision) {
      _lastMediaRevision = state.mediaRevision;
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    }
    _maybeResetInGamePage(state);
    _applySessionPower(state);
    _maybeStartCelebration(state);

    if (state.isGameLaunching) {
      _stopVideo();
      return;
    }

    // Device asleep (lid closed / screen off): tear down the preview so its
    // audio output device stops and the CPU can deep-sleep. This engine never
    // receives Android lifecycle callbacks, so deviceScreenOn (bridged from the
    // native ACTION_SCREEN_ON/OFF receiver) is the only reliable signal.
    if (!state.deviceScreenOn) {
      _stopVideo();
      _currentVideoPath = null; // force a fresh start when the screen wakes
      return;
    }

    if (state.gameVideo != _currentVideoPath) {
      _currentVideoPath = state.gameVideo;
      _stopVideo();
      if (state.isGameSelected && state.gameVideo != null) {
        _startVideoTimer(state.gameVideo!);
      }
    } else if (!state.isGameSelected) {
      _stopVideo();
    } else {
      // Game selected, same video, but maybe mute changed
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController!.setVolume(state.isVideoMuted ? 0.0 : 1.0);
      }
    }
  }

  /// Triggers (or refreshes) the celebration banner when a new set of
  /// session-earned achievements arrives, auto-clearing it after a few seconds.
  void _maybeStartCelebration(SecondaryDisplayStateData state) {
    final ids = state.newlyEarnedIds;
    final key = (ids == null || ids.isEmpty)
        ? null
        : (List<int>.from(ids)..sort()).join(',');

    if (key == _celebrationKey) return;
    _celebrationKey = key;
    _celebrationTimer?.cancel();

    if (key == null) {
      if (_celebrate && mounted) setState(() => _celebrate = false);
      return;
    }

    // Surface the unlock: Now Playing is the default page, so jump to the
    // achievements page (when present) where the celebration is visible.
    final raAvailable =
        state.showAchievementPanel && state.achievements != null;
    if (mounted) {
      setState(() {
        _celebrate = true;
        if (raAvailable) _inGamePanelPage = 1;
      });
    }
    _wakeInGamePanel();
    _celebrationTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _celebrate = false);
    });
  }

  /// Resets the in-game container to the Now Playing page (0) on each new
  /// launch — detected by the session activating, or the game id changing while
  /// it stays active.
  void _maybeResetInGamePage(SecondaryDisplayStateData state) {
    final freshLaunch =
        state.nowPlayingActive &&
        (!_wasNowPlayingActive || state.gameId != _panelGameId);
    final exited = _wasNowPlayingActive && !state.nowPlayingActive;
    _wasNowPlayingActive = state.nowPlayingActive;
    _panelGameId = state.gameId;

    if (freshLaunch) {
      _resetAchievementComments();
      _startPlayTimeTicker();
      _wakeInGamePanel();
    } else if (exited) {
      _resetAchievementComments();
      _stopPlayTimeTicker();
      _cancelDim();
    }

    if (freshLaunch && _inGamePanelPage != 0 && mounted) {
      setState(() => _inGamePanelPage = 0);
    }
  }

  void _resetAchievementComments() {
    _commentsRequestGeneration++;
    _selectedAchievement = null;
    _commentsCache.clear();
    _inGamePanelPage = 0;
  }

  Future<void> _selectAchievement(SecondaryAchievementItem achievement) async {
    SfxService().playNavSound();
    _wakeInGamePanel();
    setState(() {
      _selectedAchievement = achievement;
      _inGamePanelPage = 2;
    });
    if (!_commentsCache.containsKey(achievement.id)) {
      await _loadAchievementComments(achievement.id, reset: true);
    }
  }

  Future<void> _loadAchievementComments(
    int achievementId, {
    required bool reset,
  }) async {
    const pageSize = 25;
    final current = _commentsCache[achievementId];
    if (current?.isLoading == true) return;

    final generation = ++_commentsRequestGeneration;
    final offset = reset ? 0 : (current?.loadedRaw ?? 0);
    // Resolve the error strings up front (context is safe before the awaits
    // below) so the catch block never touches a BuildContext across an async
    // gap.
    final ctx = _l10nContext ?? context;
    final rateLimitedMessage = AppLocale.raRateLimited.getString(ctx);
    final couldNotLoadMessage = AppLocale.raCommentsCouldNotLoad.getString(ctx);
    setState(() {
      _commentsCache[achievementId] = AchievementCommentsState(
        comments: reset ? const [] : (current?.comments ?? const []),
        total: reset ? 0 : (current?.total ?? 0),
        loadedRaw: reset ? 0 : (current?.loadedRaw ?? 0),
        isLoading: true,
      );
    });

    try {
      final apiKey = await RetroAchievementsRepository.getRAApiKey();
      final page = await RetroAchievementsService.getAchievementComments(
        achievementId,
        count: pageSize,
        offset: offset,
        apiKey: apiKey,
      );
      if (!mounted || generation != _commentsRequestGeneration) return;

      final existing = reset ? <RetroAchievementComment>[] : current!.comments;
      final byKey = <String, RetroAchievementComment>{
        for (final comment in existing)
          if (!comment.isSystemComment) comment.cacheKey: comment,
      };
      for (final comment in page.results) {
        if (!comment.isSystemComment) {
          byKey[comment.cacheKey] = comment;
        }
      }
      // Advance by the raw page size (system comments included) so the next
      // offset lines up with the API's own paging. A short page means we've
      // reached the end, so pin total to what we've loaded to stop offering
      // "load more" — the raw Total can exceed the visible count because
      // system/server comments are filtered out of the display.
      final consumedRaw = page.count;
      final loadedRaw = offset + consumedRaw;
      final reachedEnd = consumedRaw < pageSize;
      setState(() {
        _commentsCache[achievementId] = AchievementCommentsState(
          comments: byKey.values.toList(),
          total: reachedEnd ? loadedRaw : page.total,
          loadedRaw: loadedRaw,
        );
      });
    } catch (error) {
      if (!mounted || generation != _commentsRequestGeneration) return;
      // Map to a friendly, localized message rather than leaking raw
      // exception text (e.g. "...request failed (429)") into the UI. HTTP 429
      // means RetroAchievements is rate-limiting us; anything else is a
      // generic load failure.
      final message = error.toString().contains('(429)')
          ? rateLimitedMessage
          : couldNotLoadMessage;
      setState(() {
        _commentsCache[achievementId] = AchievementCommentsState(
          comments: reset ? const [] : (current?.comments ?? const []),
          total: reset ? 0 : (current?.total ?? 0),
          loadedRaw: reset ? 0 : (current?.loadedRaw ?? 0),
          error: message,
        );
      });
    }
  }

  /// Restarts the session stopwatch and the per-second repaint so the live
  /// PLAY TIME counts up from zero for this launch.
  void _startPlayTimeTicker() {
    _sessionWatch
      ..reset()
      ..start();
    _armPlayTimeTicker();
  }

  /// (Re)creates the per-second repaint timer without touching the stopwatch, so
  /// it can be reused both for a fresh launch and for resuming after sleep.
  void _armPlayTimeTicker() {
    _playTimeTicker?.cancel();
    _playTimeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopPlayTimeTicker() {
    _playTimeTicker?.cancel();
    _playTimeTicker = null;
    _sessionWatch
      ..stop()
      ..reset();
  }

  /// Freezes the live session clock while the device screen is off, resuming it
  /// on wake. This engine never receives Android lifecycle callbacks (it runs in
  /// a separate FlutterEngine behind the sub_screen Presentation), and a play
  /// session runs the game in a separate app — so the only reliable "device is
  /// asleep" signal is [SecondaryDisplayStateData.deviceScreenOn], bridged from a
  /// native ACTION_SCREEN_ON/OFF receiver. Without this the [Stopwatch] keeps
  /// accruing wall-clock time while the device sleeps.
  void _applySessionPower(SecondaryDisplayStateData state) {
    if (!state.deviceScreenOn) {
      // Screen off: freeze the counter where it is.
      if (_sessionWatch.isRunning) {
        _playTimeTicker?.cancel();
        _playTimeTicker = null;
        _sessionWatch.stop();
      }
    } else if (_wasNowPlayingActive && !_sessionWatch.isRunning) {
      // Screen back on mid-session: resume from the frozen elapsed time.
      _sessionWatch.start();
      _armPlayTimeTicker();
      if (mounted) setState(() {});
    }
  }

  /// Wakes the in-game container to full brightness and (re)arms the idle dim
  /// countdown. Called on every activity event.
  void _wakeInGamePanel() {
    _dimTimer?.cancel();
    if (_inGameDimmed && mounted) {
      setState(() => _inGameDimmed = false);
    }
    // User setting: 0 seconds means "never dim", so leave the panel lit.
    final delaySeconds = _secondaryDisplayState?.value?.nowPlayingDimDelay ?? 5;
    if (delaySeconds <= 0) return;
    _dimTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) setState(() => _inGameDimmed = true);
    });
  }

  void _cancelDim() {
    _dimTimer?.cancel();
    _dimTimer = null;
    _inGameDimmed = false;
  }

  void _startVideoTimer(String path) {
    _videoTimer?.cancel();
    _videoTimer = Timer(const Duration(milliseconds: 500), () {
      _initializeVideo(path);
    });
  }

  Future<void> _initializeVideo(String path) async {
    if (!mounted) return;

    // Snapshot the generation: if _stopVideo runs (e.g. a game launches) while
    // we're awaiting below, this goes stale and we abort before playing.
    final gen = _videoGeneration;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!mounted || gen != _videoGeneration) {
        await controller.dispose();
        return;
      }

      // IMPORTANT: Set volume BEFORE playing to ensure sync and avoid audio burst
      final isMuted = _secondaryDisplayState?.value?.isVideoMuted ?? true;
      await controller.setVolume(isMuted ? 0.0 : 1.0);

      await controller.setLooping(true);
      await controller.play();

      if (!mounted || gen != _videoGeneration) {
        await controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _showVideo = true;
      });
    } catch (e) {
      debugPrint('SecondaryScreen: Error initializing video: $e');
      // Don't leak the controller if we threw after creating it.
      if (controller != null && _videoController != controller) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }
  }

  void _stopVideo() {
    // Invalidate any in-flight _initializeVideo so it discards its controller
    // rather than playing audio over a game that just launched.
    _videoGeneration++;
    _videoTimer?.cancel();
    _videoTimer = null;
    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      try {
        controller.dispose();
      } catch (e) {
        debugPrint('SecondaryScreen: Error disposing video: $e');
      }
    }
    if (mounted) {
      setState(() {
        _showVideo = false;
      });
    }
  }

  @override
  void dispose() {
    // Shared singleton — detach our listener, never dispose the instance.
    _secondaryDisplayState?.removeListener(_onStateChanged);
    _celebrationTimer?.cancel();
    _playTimeTicker?.cancel();
    _dimTimer?.cancel();
    _stopVideo();
    super.dispose();
  }

  void _toggleMute() {
    final state = _secondaryDisplayState?.value;
    if (state != null) {
      _secondaryDisplayState?.updateState(
        isVideoMuted: !state.isVideoMuted,
        muteToggleTrigger: state.muteToggleTrigger + 1,
      );
    }
  }

  /// Asks the main engine to take a system screenshot of the main screen by
  /// bumping the shared trigger; the main engine watches for the increment.
  void _requestScreenshot() {
    final state = _secondaryDisplayState?.value;
    if (state != null) {
      _wakeInGamePanel();
      _secondaryDisplayState?.updateState(
        screenshotTrigger: state.screenshotTrigger + 1,
      );
    }
  }

  /// Current dock slot assignments, always [ConfigModel.dockMaxSlots] long.
  List<String> get _dockApps {
    final apps = _secondaryDisplayState?.value?.dockApps;
    return ConfigModel.normalizeDock(apps);
  }

  /// Writes a new dock layout to shared state and bumps the edit trigger so the
  /// main engine persists it.
  void _commitDock(List<String> next) {
    final state = _secondaryDisplayState?.value;
    if (state == null) return;
    _secondaryDisplayState?.updateState(
      dockApps: next,
      dockEditTrigger: state.dockEditTrigger + 1,
    );
  }

  /// Opens the app picker for [slot], lazily loading the installed-app list.
  Future<void> _openAppPicker(int slot) async {
    _wakeInGamePanel();
    SfxService().playNavSound();
    setState(() {
      _pickerSlot = slot;
      _launcherOpen = false;
    });
    await _ensurePickerApps();
  }

  /// Opens the picker as a full app launcher: tapping a tile launches the app
  /// instead of assigning it to a dock slot.
  Future<void> _openAppLauncher() async {
    _wakeInGamePanel();
    SfxService().playNavSound();
    setState(() {
      _launcherOpen = true;
      _pickerSlot = null;
    });
    await _ensurePickerApps();
  }

  /// Lazily loads the installed-app list backing the picker/launcher, once.
  Future<void> _ensurePickerApps() async {
    if (_pickerApps != null || _loadingPickerApps) return;
    setState(() => _loadingPickerApps = true);
    final apps = await SecondaryAppsService.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _pickerApps = apps;
      _loadingPickerApps = false;
    });
  }

  void _closeAppPicker() {
    setState(() {
      _pickerSlot = null;
      _launcherOpen = false;
    });
  }

  /// Assigns [package] to the pending picker slot and closes the picker.
  void _assignSlot(String package) {
    final slot = _pickerSlot;
    if (slot == null) return;
    final next = List<String>.from(_dockApps);
    if (slot >= 0 && slot < next.length) {
      next[slot] = package;
      _commitDock(next);
    }
    _closeAppPicker();
  }

  /// Empties dock [slot] (long-press on a filled slot).
  void _clearSlot(int slot) {
    _wakeInGamePanel();
    SfxService().playNavSound();
    final next = List<String>.from(_dockApps);
    if (slot >= 0 && slot < next.length) {
      next[slot] = '';
      _commitDock(next);
    }
  }

  /// Launches a docked app, preferring the bottom display.
  void _launchDockApp(String package) {
    _wakeInGamePanel();
    SfxService().playNavSound();
    SecondaryAppsService.launchAppOnSecondary(package);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(640, 480),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) => ValueListenableBuilder<SecondaryDisplayStateData?>(
        valueListenable: _secondaryDisplayState ?? ValueNotifier(null),
        builder: (context, value, child) {
          final theme = resolveTheme(value?.themeName);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            // Suppress Android's overscroll glow/stretch: on this display a
            // slight drag near the edge would flash white arcs at the screen
            // border, which looks like a rendering glitch on a static panel.
            scrollBehavior: const NoGlowScrollBehavior(),
            theme: theme.copyWith(
              scaffoldBackgroundColor: value?.backgroundColor != null
                  ? Color(value!.backgroundColor!)
                  : theme.scaffoldBackgroundColor,
              // Match the primary app: default all text to the neostation
              // (Anta) font so the secondary display stays on-brand.
              textTheme: GoogleFonts.antaTextTheme(theme.textTheme),
            ),
            home: Builder(
              builder: (context) {
                // Capture a context from under this MaterialApp's Localizations
                // so the _buildXxx helpers can resolve AppLocale strings.
                _l10nContext = context;
                return Scaffold(
                  backgroundColor: value?.backgroundColor != null
                      ? Color(value!.backgroundColor!)
                      : Colors.black,
                  body: value == null
                      ? _buildDefaultStaticUI()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            // Base layer: Shader/App background (Conditional)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 256),
                              child: SizedBox.expand(
                                key: ValueKey(
                                  'secondary_bg_${value.isGameSelected}_${value.systemName}_${value.backgroundColor}_${value.isOled}',
                                ),
                                child:
                                    (value.isGameSelected ||
                                        value.useFluidShader)
                                    ? buildUnifiedAppBackground(value)
                                    : buildSystemBackground(value),
                              ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                            ),

                            // Game Layer: Screenshot/Video (on top of shader)
                            if (value.isGameSelected)
                              Stack(
                                fit: StackFit.expand,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 256),
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                    child: Stack(
                                      key: ValueKey(
                                        'game_content_${value.systemName}_${value.gameId}_${value.gameScreenshot ?? 'none'}_${value.gameFanart ?? 'none'}_${value.gameWheel ?? 'none'}_${value.gameImageBytes != null ? value.gameImageBytes.hashCode : 'none'}_${value.mediaRevision}',
                                      ),
                                      fit: StackFit.expand,
                                      children: [
                                        // Only show background images IF video is NOT showing (user request: "quitando del fondo el screenshot")
                                        if (!_showVideo) ...[
                                          if (value.isGameLaunching) ...[
                                            if (value.gameImageBytes != null)
                                              buildBackgroundBytes(
                                                value.gameImageBytes!,
                                                fit: BoxFit
                                                    .contain, // "se debe ver completo"
                                              )
                                            else if (value.gameScreenshot !=
                                                null)
                                              buildBackground(
                                                value.gameScreenshot!,
                                                fit: BoxFit
                                                    .contain, // "se debe ver completo"
                                              )
                                            else if (value.gameFanart != null ||
                                                value.gameWheel != null)
                                              buildFanartWithLogo(value),
                                          ] else ...[
                                            if (value.gameImageBytes != null)
                                              buildBackgroundBytes(
                                                value.gameImageBytes!,
                                                fit: BoxFit
                                                    .contain, // "se debe ver completo"
                                              )
                                            else if (value.gameScreenshot !=
                                                null)
                                              buildBackground(
                                                value.gameScreenshot!,
                                                fit: BoxFit
                                                    .contain, // "se debe ver completo"
                                              )
                                            else if (value.gameFanart != null ||
                                                value.gameWheel != null)
                                              buildFanartWithLogo(value),
                                          ],
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (_showVideo && _videoController != null)
                                    SizedBox.expand(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: SizedBox(
                                          width: _videoController!
                                              .value
                                              .size
                                              .width,
                                          height: _videoController!
                                              .value
                                              .size
                                              .height,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                            // In-game paged container: Now Playing (page 0) and,
                            // when the game has a RetroAchievements set, the
                            // achievements panel (page 1). Touch-paged via edge
                            // chevrons; covers the game art, fading in on launch
                            // and out on return.
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: !value.nowPlayingActive,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  child: value.nowPlayingActive
                                      ? KeyedSubtree(
                                          key: const ValueKey('in-game-panel'),
                                          child: _buildInGamePanel(value),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey('in-game-panel-empty'),
                                        ),
                                ),
                              ),
                            ),

                            // Center Content (system/recent-game logo). Suppressed
                            // while the in-game container is up so the logo doesn't
                            // draw on top of it (recent-game launches push state
                            // with isGameSelected: false + the wheel as systemLogo).
                            if (!value.isGameSelected &&
                                !value.nowPlayingActive)
                              _buildCenterContent(
                                value,
                                isTab: value.useFluidShader,
                              ),

                            if (value.isGameSelected && _showVideo)
                              Positioned(
                                bottom: 24.r,
                                right: 24.r,
                                child: GestureDetector(
                                  onTap: () {
                                    SfxService().playNavSound();
                                    _toggleMute();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.r,
                                      vertical: 10.r,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(12.r),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        width: 1.r,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Image.asset(
                                          'assets/images/gamepad/Xbox_Menu_button.png',
                                          width: 32.r,
                                          height: 32.r,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 12.r),
                                        Icon(
                                          value.isVideoMuted
                                              ? Symbols.volume_off_rounded
                                              : Symbols.volume_up_rounded,
                                          color: Colors.white,
                                          size: 24.r,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            // Persistent app dock + all-apps launcher. Drawn at
                            // the top level (not inside the in-game panel) so it
                            // stays visible while browsing systems and on the
                            // Now Playing page — hidden on the achievement pages
                            // and dimmed together with the panel's idle scrim.
                            if (value.dockEnabled) _buildDockOverlay(value),

                            // Scraping Overlay
                            _buildScrapingOverlay(value),

                            // App picker overlay (dock-slot assignment or
                            // all-apps launcher). Top-most so it covers the dock
                            // and any panel; available in every state.
                            if (_pickerVisible) _buildAppPickerOverlay(),

                            // Accessibility explainer, top-most so it sits over
                            // the dock and picker.
                            if (_accessDialogVisible)
                              _buildAccessibilityDialog(value),
                          ],
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDefaultLogo() {
    return Image.asset(
      'assets/images/logo_transparent.png',
      width: 200.r,
      height: 200.r,
      fit: BoxFit.contain,
    );
  }

  Widget _buildSystemLogo(SecondaryDisplayStateData value) {
    if (value.systemLogo == null) return _buildDefaultLogo();

    final double logoSize = 460.r;

    if (value.isLogoAsset) {
      return Image.asset(
        value.systemLogo!,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(),
      );
    } else {
      final file = File(value.systemLogo!);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(),
        );
      }
    }
    return _buildDefaultLogo();
  }

  Widget _buildDefaultStaticUI() {
    return Stack(
      fit: StackFit.expand,
      children: [
        buildDefaultBackground(),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDefaultLogo(),
              SizedBox(height: 40.r),
              _buildSystemNameContainer('WELCOME'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterContent(
    SecondaryDisplayStateData value, {
    bool isTab = false,
  }) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 256),
        child: Column(
          key: ValueKey(
            'system_center_${value.systemName}_${value.systemLogo}_$isTab',
          ),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isTab) ...[
              _buildSystemLogo(value),
              if (value.systemLogo == null) ...[
                SizedBox(height: 40.r),
                _buildSystemNameContainer(
                  value.systemName.isEmpty ? 'WELCOME' : value.systemName,
                ),
              ],
            ] else ...[
              _buildDefaultLogo(),
              SizedBox(height: 8.r),
              _buildSystemNameContainer(value.systemName.toUpperCase()),
            ],
          ],
        ),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSystemNameContainer(String name) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 12.r),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        border: Border.all(color: Colors.white24, width: 2.r),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        name.toUpperCase(),
        style: TextStyle(
          color: Colors.white70,
          fontSize: 18.r,
          letterSpacing: 6.r,
          fontWeight: FontWeight.w500,
          fontFamily: 'Anta',
        ),
      ),
    );
  }

  /// The persistent app dock + all-apps launcher overlay, drawn above the
  /// in-game panel so it stays reachable while browsing systems and on the Now
  /// Playing page.
  ///
  /// Two behaviours mirror the Now Playing panel so the dock reads as part of
  /// it while a game is active:
  ///  * Hidden while flipped to an achievements/comments page (the dock belongs
  ///    to the Now Playing page).
  ///  * Faded toward black in step with the panel's idle-dim scrim (which sits
  ///    below this overlay), so the whole display darkens uniformly.
  ///
  /// While browsing (no game active) neither applies, so the dock is fully lit
  /// and interactive.
  Widget _buildDockOverlay(SecondaryDisplayStateData value) {
    // `appReady` is a one-way "main UI has painted" latch, but the shared state
    // is written by BOTH engines: the secondary's own pushes (isSecondaryActive,
    // mute/screenshot toggles) copyWith from a local snapshot that may still
    // carry appReady=false, so the incoming flag oscillates. Latch it locally on
    // first true and ignore later falses, so the dock slides up once and stays.
    if (value.appReady) _dockRevealed = true;
    final raAvailable =
        value.showAchievementPanel && value.achievements != null;
    // Off the Now Playing page (achievements/comments) → hide the dock.
    final hidden =
        value.nowPlayingActive && raAvailable && _inGamePanelPage >= 1;
    final dimmed = value.nowPlayingActive && _inGameDimmed;
    // Fade to black alongside the panel scrim behind us: the scrim darkens the
    // display to `nowPlayingDimLevel`, so drop the dock's opacity to match and
    // let that black show through.
    final opacity = hidden
        ? 0.0
        : dimmed
        ? (1.0 - value.nowPlayingDimLevel.clamp(0, 100) / 100.0)
        : 1.0;
    return Positioned.fill(
      child: IgnorePointer(
        // Non-interactive while hidden or dimmed — when dimmed, touches fall
        // through to the panel's wake Listener below (first touch only wakes).
        ignoring: hidden || dimmed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: opacity,
          // Slide-up keyed to main-UI readiness: the dock starts parked fully
          // below the bottom edge (t=1) and stays there until the main engine
          // reports its first frame via `appReady`, then eases into place. This
          // syncs the dock's arrival with the app becoming usable instead of
          // firing on the secondary display's own (earlier) first paint.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: _dockRevealed ? 0.0 : 1.0),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Transform.translate(
              offset: Offset(0, t * 140.r),
              child: child,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AppDock(
                    value: value,
                    onLaunchApp: _launchDockApp,
                    onPickSlot: _openAppPicker,
                    onClearSlot: _clearSlot,
                    onOpenAccessibilitySettings: _showAccessibilityDialog,
                  ),
                ),
                Positioned(
                  left: 16.r,
                  bottom: 16.r,
                  child: DockLauncherButton(
                    value: value,
                    onOpenLauncher: _openAppLauncher,
                    onOpenAccessibilitySettings: _showAccessibilityDialog,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The in-game container body: shows the Now Playing page or the
  /// achievements/comments pages, with edge chevrons to flip between them when the game
  /// has a RetroAchievements set. The page index is clamped so the RA page is
  /// only shown when it actually exists.
  Widget _buildInGamePanel(SecondaryDisplayStateData value) {
    final raAvailable =
        value.showAchievementPanel && value.achievements != null;
    final commentsAvailable =
        raAvailable && _selectedAchievement != null && _inGamePanelPage == 2;
    final page = commentsAvailable
        ? 2
        : (_inGamePanelPage == 1 && raAvailable)
        ? 1
        : 0;

    // Idle-dim wrapper: any touch wakes the panel (translucent so it never
    // swallows chevron taps). Once the idle countdown elapses a full-bleed black
    // scrim fades in over everything — panel and background art alike — so the
    // display goes to near-black regardless of the current theme.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wakeInGamePanel(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildInGamePanelBody(value, raAvailable, page),
          Positioned.fill(
            // While dimmed, the opaque scrim swallows touches so buttons
            // underneath don't fire — the outer Listener still wakes the panel,
            // so the first touch only wakes (no accidental presses). When awake,
            // ignore the scrim entirely so touches reach the buttons.
            child: IgnorePointer(
              ignoring: !_inGameDimmed,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _inGameDimmed
                    ? value.nowPlayingDimLevel.clamp(0, 100) / 100.0
                    : 0.0,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInGamePanelBody(
    SecondaryDisplayStateData value,
    bool raAvailable,
    int page,
  ) {
    return Stack(
      children: [
        // Opaque backdrop: while the two pages cross-fade they are both
        // briefly translucent, so without this the game-art layer underneath
        // the container would bleed through during the transition.
        Positioned.fill(
          child: ColoredBox(
            color: value.backgroundColor != null
                ? Color(value.backgroundColor!)
                : Colors.black,
          ),
        ),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey('in-game-page-$page'),
              child: page == 2
                  ? AchievementCommentsPage(
                      achievement: _selectedAchievement!,
                      state: _commentsCache[_selectedAchievement!.id],
                      l10nContext: _l10nContext,
                      onLoadComments: _loadAchievementComments,
                    )
                  : page == 1
                  ? AchievementPanel(
                      value: value,
                      listView: _achievementListView,
                      celebrate: _celebrate,
                      l10nContext: _l10nContext,
                      onToggleListView: () {
                        SfxService().playNavSound();
                        setState(
                          () => _achievementListView = !_achievementListView,
                        );
                      },
                      onSelectAchievement: _selectAchievement,
                    )
                  : NowPlayingPanel(
                      value: value,
                      sessionRunning: _sessionWatch.isRunning,
                      sessionTime: _formatSessionTime(),
                      onRequestScreenshot: _requestScreenshot,
                    ),
            ),
          ),
        ),
        // Edge chevrons: only meaningful when there are two pages. The chevron
        // points toward the page it reveals (right on Now Playing, left on RA).
        if (raAvailable && page == 0) _buildPageChevron(left: false),
        if (raAvailable && page == 1) _buildPageChevron(left: true),
        if (page == 2) _buildPageChevron(left: true, destinationPage: 1),
      ],
    );
  }

  /// A translucent circular chevron pinned to the left/right edge that flips
  /// the in-game page. Styled like the mute toggle.
  Widget _buildPageChevron({required bool left, int? destinationPage}) {
    return Positioned(
      left: left ? 12.r : null,
      right: left ? null : 12.r,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            SfxService().playNavSound();
            _wakeInGamePanel();
            setState(
              () => _inGamePanelPage = destinationPage ?? (left ? 0 : 1),
            );
          },
          child: Container(
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.r,
              ),
            ),
            child: Icon(
              left
                  ? Symbols.chevron_left_rounded
                  : Symbols.chevron_right_rounded,
              color: Colors.white,
              size: 30.r,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens Android accessibility settings from the secondary engine so the user
  /// can enable the Screen Return service.
  void _openAccessibilitySettings() {
    _wakeInGamePanel();
    SfxService().playNavSound();
    SecondaryAppsService.openAccessibilitySettings();
  }

  /// Shows the explainer dialog raised when the launcher is tapped while the
  /// Screen Return accessibility service is off.
  void _showAccessibilityDialog() {
    _wakeInGamePanel();
    SfxService().playNavSound();
    setState(() => _accessDialogVisible = true);
  }

  void _dismissAccessibilityDialog() {
    SfxService().playNavSound();
    setState(() => _accessDialogVisible = false);
  }

  /// Accepts the explainer: closes it and jumps to accessibility settings.
  void _confirmAccessibilityDialog() {
    setState(() => _accessDialogVisible = false);
    _openAccessibilitySettings();
  }

  /// Modal explainer shown before sending the user to accessibility settings.
  /// Tells them why the Screen Return service is needed and what to do once the
  /// settings screen opens. Tapping the backdrop or CANCEL dismisses; OPEN
  /// SETTINGS jumps straight to the accessibility page.
  Widget _buildAccessibilityDialog(SecondaryDisplayStateData value) {
    final scheme = panelScheme(value);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissAccessibilityDialog,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: GestureDetector(
              // Swallow taps on the card so they don't dismiss via the backdrop.
              onTap: () {},
              child: Container(
                width: 480.r,
                padding: EdgeInsets.all(28.r),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 24.r,
                      offset: Offset(0, 8.r),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Symbols.accessibility_new_rounded,
                          color: scheme.primary,
                          size: 30.r,
                        ),
                        SizedBox(width: 12.r),
                        Expanded(
                          child: Text(
                            'Enable Screen Return',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 20.r,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 18.r),
                    Text(
                      'To launch apps from the dock, NeoStation needs the '
                      'Screen Return accessibility service. It lets NeoStation '
                      'bring you back here after you close the app you opened. '
                      "Without it you could be left with no way back.\n\n"
                      'On the next screen, find NeoStation in the list of '
                      'services and switch it on.',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 14.r,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: 26.r),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildDialogButton(
                          label: 'CANCEL',
                          onTap: _dismissAccessibilityDialog,
                          scheme: scheme,
                          filled: false,
                        ),
                        SizedBox(width: 12.r),
                        _buildDialogButton(
                          label: 'OPEN SETTINGS',
                          onTap: _confirmAccessibilityDialog,
                          scheme: scheme,
                          filled: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A flat dialog action button — filled with the accent for the primary
  /// action, outlined for the secondary. Custom (not a Material button) to match
  /// the rest of the secondary screen, which has no Material ancestor.
  Widget _buildDialogButton({
    required String label,
    required VoidCallback onTap,
    required ColorScheme scheme,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.r, vertical: 12.r),
        decoration: BoxDecoration(
          color: filled ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: filled
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.30),
            width: 1.5.r,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? scheme.onPrimary : scheme.onSurface,
            fontSize: 13.r,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.r,
          ),
        ),
      ),
    );
  }

  /// Full-panel overlay for choosing an app for the pending dock slot. Tapping
  /// the backdrop cancels; tapping an app assigns it.
  Widget _buildAppPickerOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeAppPicker,
        child: ColoredBox(
          // Fully opaque so the Now Playing screen behind is not visible while
          // choosing an app for a dock slot.
          color: Colors.black,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20.r),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        _launcherOpen ? 'LAUNCH AN APP' : 'CHOOSE AN APP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.r,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.r,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _closeAppPicker,
                        child: Icon(
                          Symbols.close_rounded,
                          color: Colors.white,
                          size: 26.r,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.r),
                  Expanded(child: _buildAppPickerGrid()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppPickerGrid() {
    if (_loadingPickerApps || _pickerApps == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final apps = _pickerApps!;
    if (apps.isEmpty) {
      return Center(
        child: Text(
          'No apps found',
          style: TextStyle(color: Colors.white70, fontSize: 14.r),
        ),
      );
    }
    // Swallow taps inside the grid so they don't hit the dismiss backdrop.
    return GestureDetector(
      onTap: () {},
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 128.r,
          mainAxisSpacing: 20.r,
          crossAxisSpacing: 20.r,
          childAspectRatio: 0.82,
        ),
        itemCount: apps.length,
        itemBuilder: (context, i) {
          final app = apps[i];
          final package = (app['package'] ?? '').toString();
          final name = (app['name'] ?? package).toString();
          return _buildPickerTile(package, name);
        },
      ),
    );
  }

  /// Handles a picker-tile tap: launches the app in launcher mode, otherwise
  /// assigns it to the pending dock slot.
  void _onPickerTileTap(String package) {
    if (_launcherOpen) {
      _closeAppPicker();
      _launchDockApp(package);
    } else {
      _assignSlot(package);
    }
  }

  Widget _buildPickerTile(String package, String name) {
    return GestureDetector(
      onTap: package.isEmpty ? null : () => _onPickerTileTap(package),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84.r,
            height: 84.r,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18.r),
            ),
            padding: EdgeInsets.all(12.r),
            child: buildDockIcon(package),
          ),
          SizedBox(height: 8.r),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 10.r),
          ),
        ],
      ),
    );
  }

  /// The running session length, formatted down to the second so the per-second
  /// tick is visible. Shown alongside the (static) total PLAY TIME while a game
  /// is active.
  String _formatSessionTime() {
    final total = _sessionWatch.elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m '
          '${s.toString().padLeft(2, '0')}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  Widget _buildScrapingOverlay(SecondaryDisplayStateData value) {
    if (value.isGameLaunching) return const SizedBox.shrink();

    return Positioned(
      bottom: 24.r,
      left: 24.r,
      right: 24.r,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scraping Progress
          if (value.isScraping)
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 20.r,
                    offset: Offset(0, 8.r),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 20.r,
                        height: 20.r,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      ),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: Text(
                          value.scrapeStatus ?? 'Scrapeando...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.r,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Anta',
                          ),
                        ),
                      ),
                      if (value.scrapeProgress != null)
                        Text(
                          '${(value.scrapeProgress! * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 16.r,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Anta',
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 12.r),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: value.scrapeProgress,
                      minHeight: 6.r,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

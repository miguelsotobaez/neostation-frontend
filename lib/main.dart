import 'package:neostation/providers/menu_app_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/providers/scraping_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/neo_sync_provider.dart';
import 'package:neostation/screens/main_screen.dart';
import 'package:neostation/services/neosync/auth_service.dart';
import 'package:neostation/services/neosync/neo_sync_service.dart';
import 'package:neostation/services/neosync/billing_service.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/sync/providers/neo_sync_adapter.dart';
import 'package:neostation/services/notification_service.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/game_legend_visibility.dart';
import 'package:neostation/repositories/config_repository.dart';
import 'package:neostation/services/steam_scraper_service.dart';
import 'package:neostation/providers/system_background_provider.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/widgets/app_lifecycle_handler.dart';
import 'package:neostation/services/startup_theme_cache.dart';
import 'package:neostation/widgets/shimmering_logo.dart';
import 'package:neostation/widgets/permission_check_wrapper.dart';
import 'package:neostation/utils/custom_scroll_behavior.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:fvp/fvp.dart';
import 'package:fullscreen_window/fullscreen_window.dart';
import 'package:window_manager/window_manager.dart';
import 'package:neostation/screens/secondary_screen/secondary_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';

// Politica personalizada para deshabilitar navegacion por teclado
class NoFocusTraversalPolicy extends FocusTraversalPolicy {
  @override
  FocusNode? findFirstFocus(
    FocusNode currentNode, {
    bool ignoreCurrentFocus = false,
  }) => null;

  @override
  FocusNode? findFirstFocusInDirection(
    FocusNode currentNode,
    TraversalDirection direction,
  ) => null;

  @override
  FocusNode findLastFocus(
    FocusNode currentNode, {
    bool ignoreCurrentFocus = false,
  }) => currentNode;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) =>
      false;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => [];
}

// Notifier global para cambios de fullscreen
class FullscreenNotifier extends ChangeNotifier {
  static final FullscreenNotifier _instance = FullscreenNotifier._internal();
  factory FullscreenNotifier() => _instance;
  FullscreenNotifier._internal();

  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

  void notifyFullscreenChanged(bool isFullscreen) {
    if (_isFullscreen != isFullscreen) {
      _isFullscreen = isFullscreen;
      LoggerService.instance.i(
        'FullscreenNotifier: Fullscreen changed to $isFullscreen',
      );
      notifyListeners();
    }
  }
}

// Intent para toggle fullscreen
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

// Action para toggle fullscreen
class ToggleFullscreenAction extends Action<ToggleFullscreenIntent> {
  @override
  Future<void> invoke(ToggleFullscreenIntent intent) async {
    if (Platform.isWindows || Platform.isLinux) {
      final isFullscreen = FullscreenNotifier().isFullscreen;
      final newState = !isFullscreen;
      LoggerService.instance.i('Toggle fullscreen (Native): $newState');
      FullScreenWindow.setFullScreen(newState);

      // Notificar el cambio de fullscreen
      FullscreenNotifier().notifyFullscreenChanged(newState);
    } else if (Platform.isMacOS) {
      final isFullscreen = await windowManager.isFullScreen();
      LoggerService.instance.i(
        'Toggle fullscreen (macOS): current=$isFullscreen, setting=${!isFullscreen}',
      );
      await windowManager.setFullScreen(!isFullscreen);

      // Notificar el cambio de fullscreen
      await Future.delayed(const Duration(milliseconds: 100));
      final newState = await windowManager.isFullScreen();
      FullscreenNotifier().notifyFullscreenChanged(newState);
    }
    return;
  }
}

/// Configures the Flutter [ImageCache] based on platform and available RAM.
///
/// Android: reads total memory via [DeviceInfoPlugin] and applies tiered limits.
/// Desktop (Windows/macOS/Linux): applies generous defaults.
Future<void> _configureImageCache() async {
  try {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      LoggerService.instance.i(
        'Android device detected: ${info.model}, RAM: ${info.physicalRamSize} MB',
      );
      final ramGb = info.physicalRamSize ~/ 1024;
      LoggerService.instance.i(
        'Configuring image cache for Android device with $ramGb GB RAM',
      );
      int maxBytes;
      int maxSize;

      if (ramGb <= 2) {
        maxBytes = 40 * 1024 * 1024;
        maxSize = 300;
      } else if (ramGb <= 4) {
        maxBytes = 80 * 1024 * 1024;
        maxSize = 600;
      } else if (ramGb <= 8) {
        maxBytes = 200 * 1024 * 1024;
        maxSize = 1000;
      } else {
        maxBytes = 400 * 1024 * 1024;
        maxSize = 1500;
      }

      LoggerService.instance.i(
        'Setting image cache limits: maxSize=$maxSize, maxBytes=${maxBytes ~/ (1024 * 1024)} MB',
      );

      PaintingBinding.instance.imageCache.maximumSize = maxSize;
      PaintingBinding.instance.imageCache.maximumSizeBytes = maxBytes;
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      PaintingBinding.instance.imageCache.maximumSize = 2000;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 400 * 1024 * 1024;
    } else {
      PaintingBinding.instance.imageCache.maximumSize = 1000;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
    }
  } catch (_) {
    PaintingBinding.instance.imageCache.maximumSize = 1000;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
  }
}

/// Global navigator key so overlay notifications can outlive the widget that
/// created them. Used by [AppNotification] for progress notifications.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Render immediately. Cold boots can wait for removable storage before the
  // database opens, and without this lightweight root Android shows only a
  // blank launch surface for that entire interval.
  runApp(const StartupLoadingApp());
  await WidgetsBinding.instance.endOfFrame;

  await _configureImageCache();

  final log = LoggerService.instance;
  await log.init();
  log.i('Starting NeoStation...');

  // Resolve the user-data location before anything reads it, so the cold-boot
  // wait happens once (behind the loading screen) rather than once per caller.
  if (Platform.isAndroid) {
    await _awaitUserDataStorage();
  }

  // Inicializar window_manager para desktop con tamano minimo 640x480
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = WindowOptions(
      size: const Size(1280, 720),
      alwaysOnTop: false,
      skipTaskbar: false,
      minimumSize: const Size(640, 480),
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // Cargar configuracion de fullscreen
    bool isFullscreen = true;
    try {
      final config = await ConfigRepository.getUserConfig();
      if (config != null && config['is_fullscreen'] != null) {
        isFullscreen = config['is_fullscreen'] == 1;
      }
    } catch (e) {
      LoggerService.instance.w('Error loading fullscreen config: $e');
    }

    if (isFullscreen) {
      if (Platform.isWindows || Platform.isLinux) {
        FullScreenWindow.setFullScreen(true);
      } else if (Platform.isMacOS) {
        await windowManager.setFullScreen(true);
      }
      FullscreenNotifier().notifyFullscreenChanged(true);
    } else {
      if (Platform.isWindows || Platform.isLinux) {
        FullScreenWindow.setFullScreen(false);
      } else if (Platform.isMacOS) {
        await windowManager.setFullScreen(false);
      }
      FullscreenNotifier().notifyFullscreenChanged(false);
    }

    log.i('Window manager initialized');
  }

  // Inicializar fvp para soporte extendido de video (Windows, Linux, etc.)
  registerWith();

  // Configurar manejo global de errores para evitar crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    // Para otros errores, usar el handler por defecto en debug
    if (details.stack != null) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  // Configure fullscreen for mobile platforms
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      //DeviceOrientation.portraitUp,
      //DeviceOrientation.portraitDown,
    ]);
  }

  // Inicializar FileProvider
  final fileProvider = FileProvider();
  try {
    await fileProvider.initialize();
  } catch (e) {
    log.e('Error initializing FileProvider: $e');
  }

  // Inicializar localizacion con idioma persistido
  String initLang = 'en';
  try {
    final rawConfig = await ConfigRepository.getUserConfig();
    if (rawConfig != null && rawConfig['app_language'] != null) {
      initLang = rawConfig['app_language'].toString();
    }
  } catch (e) {
    log.w('Could not load saved language, defaulting to en: $e');
  }
  await FlutterLocalization.instance.ensureInitialized();
  FlutterLocalization.instance.init(
    mapLocales: [
      MapLocale('en', AppLocale.en),
      MapLocale('es', AppLocale.es),
      MapLocale('pt', AppLocale.pt),
      MapLocale('ru', AppLocale.ru),
      MapLocale('zh', AppLocale.zh),
      MapLocale('zh_Hant', AppLocale.zhHant),
      MapLocale('fr', AppLocale.fr),
      MapLocale('de', AppLocale.de),
      MapLocale('it', AppLocale.it),
      MapLocale('id', AppLocale.id),
      MapLocale('ja', AppLocale.ja),
      MapLocale('ko', AppLocale.ko),
    ],
    initLanguageCode: initLang.isNotEmpty ? initLang : 'en',
  );

  // Inicializar AuthService antes de mostrar la app
  final authService = AuthService();
  await authService.initialize();

  // Inicializar providers criticos
  final sqliteConfigProvider = SqliteConfigProvider();
  final sqliteDatabaseProvider = SqliteDatabaseProvider();

  try {
    // 1. Inicializar ConfigProvider primero (sincroniza sistemas)
    await sqliteConfigProvider.initialize();

    // Seed the game legend visibility from persisted config and wire its
    // persistence sink so the Select + B toggle survives restarts/upgrades.
    GameLegendVisibility.bind(
      initialHidden: sqliteConfigProvider.config.legendHidden,
      persist: sqliteConfigProvider.updateLegendHidden,
    );

    // 2. Inicializar DatabaseProvider (carga juegos basandose en sistemas sincronizados)
    await sqliteDatabaseProvider.initialize(
      romFolders: sqliteConfigProvider.config.romFolders,
      availableSystems: sqliteConfigProvider.availableSystems,
    );

    // Background scrape Windows games from Steam
    SteamScraperService.scrapeSteamGames(provider: sqliteDatabaseProvider);
  } catch (e) {
    log.e('Error initializing database providers: $e');
  }

  // Inicializar listener de Android para tracking de tiempo de juego
  if (Platform.isAndroid) {
    try {
      GameService.initializeAndroidGameListener();
      // Verificar si hay una sesion de juego pendiente (app fue matada)
      await GameService.checkPendingGameSession();
    } catch (e) {
      log.e('Error initializing GameService: $e');
    }
  }

  // Resolve the saved theme before the first themed frame. Created lazily,
  // ThemeProvider would paint its platform-brightness fallback until the
  // database read returned — a white flash on any platform that reports a
  // light brightness (the Steam Deck does) for a user on a dark theme.
  final themeProvider = await ThemeProvider.create();

  // Build NeoSync provider graph before runApp so SyncManager can register it.
  final neoSyncService = NeoSyncService();
  final neoSyncProvider = NeoSyncProvider(neoSyncService);
  neoSyncProvider.setAuthService(authService);
  authService.addListener(() {
    neoSyncProvider.setAuthService(authService);
  });

  final neoSyncAdapter = NeoSyncAdapter(neoSyncProvider);
  SyncManager.instance.register(neoSyncAdapter);
  SyncManager.instance.restoreActive(
    sqliteConfigProvider.config.activeSyncProvider,
  );

  runApp(
    MyApp(
      fileProvider: fileProvider,
      authService: authService,
      sqliteConfigProvider: sqliteConfigProvider,
      sqliteDatabaseProvider: sqliteDatabaseProvider,
      neoSyncService: neoSyncService,
      neoSyncProvider: neoSyncProvider,
      themeProvider: themeProvider,
    ),
  );

  // Background music initialization removed

  // Initialize SFX service for navigation sounds (fire-and-forget).
  SfxService().init().then((_) {
    // Apply the persisted enabled/disabled preference immediately.
    SfxService().setEnabled(sqliteConfigProvider.config.sfxEnabled);
  });
}

/// Startup strings for the current device locale.
///
/// The startup screens run before [FlutterLocalization] is initialized (the
/// saved app language lives in the database, which may still be on a mounting
/// SD card), so they read the raw locale maps directly. Unsupported device
/// locales fall back to English — the same default the app itself uses — and
/// missing keys degrade to an empty string rather than crashing the very
/// first frame.
Map<String, dynamic> _startupStrings() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final languageTag = locale.toLanguageTag().replaceAll('-', '_');
  const translations = <String, Map<String, dynamic>>{
    'en': appLocaleEn,
    'es': appLocaleEs,
    'pt': appLocalePt,
    'ru': appLocaleRu,
    'zh': appLocaleZh,
    'zh_Hant': appLocaleZhHant,
    'fr': appLocaleFr,
    'de': appLocaleDe,
    'it': appLocaleIt,
    'id': appLocaleId,
    'ja': appLocaleJa,
    'ko': appLocaleKo,
  };
  return translations[languageTag] ??
      translations[locale.languageCode] ??
      appLocaleEn;
}

String _startupString(String key) {
  final value = _startupStrings()[key];
  return value is String ? value : '';
}

/// Shared chrome for the pre-initialization screens: logo, wordmark and a
/// caller-supplied status area.
///
/// These screens run before the database is readable, so they cannot ask
/// [ThemeProvider] for the selected theme. They read the palette mirrored into
/// [StartupThemeCache] on the last theme change instead, which keeps the whole
/// intro in the user's theme rather than always-dark chrome.
class _StartupScaffold extends StatefulWidget {
  const _StartupScaffold({
    required this.childrenBuilder,
    this.onKeyEvent,
    this.animatedLogo = false,
  });

  /// Builds the status area, given the resolved startup palette.
  final List<Widget> Function(StartupThemeColors colors) childrenBuilder;

  /// Show the shimmering logo instead of the static one. Used by the loading
  /// screen, where the shine doubles as the activity indicator; the error
  /// screen keeps the static logo (a shine would imply progress).
  final bool animatedLogo;

  /// Raw key handler used by the error screen. The gamepad navigation manager
  /// is not running this early, so gamepad buttons are read straight from the
  /// key events instead.
  final KeyEventResult Function(KeyEvent)? onKeyEvent;

  @override
  State<_StartupScaffold> createState() => _StartupScaffoldState();
}

class _StartupScaffoldState extends State<_StartupScaffold> {
  /// Starts on the dark chrome — the same color the Android splash hands over
  /// — and is replaced once the cache read returns. That read is a fast
  /// preferences lookup, so on a light theme the handoff lands within the
  /// first frames rather than being visible as a change of screen.
  StartupThemeColors _colors = StartupThemeColors.fallback;

  @override
  void initState() {
    super.initState();
    StartupThemeCache.load().then((colors) {
      if (mounted) setState(() => _colors = colors);
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.childrenBuilder(_colors);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _colors.themeData,
      home: Scaffold(
        // Matches the selected theme's scaffold color so the handoff into the
        // themed splash doesn't read as a background jump.
        backgroundColor: _colors.background,
        body: Focus(
          autofocus: widget.onKeyEvent != null,
          onKeyEvent: widget.onKeyEvent == null
              ? null
              : (_, event) => widget.onKeyEvent!(event),
          // Animated mode pins the logo at the exact screen centre — the same
          // spot the Android 12+ splash icon occupies — with the status text
          // hung below centre, so the native→Flutter handoff and the later
          // screens never move the logo. The error screen keeps the simpler
          // centred column with the wordmark.
          child: widget.animatedLogo
              ? Stack(
                  children: [
                    const Center(child: ShimmeringLogo()),
                    Align(
                      // Same offset as the scan splash's progress detail so
                      // the text/progress zone is one fixed place all intro.
                      alignment: const Alignment(0, 0.55),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo_transparent.png',
                          width: 112,
                          height: 112,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'NeoStation',
                          style: TextStyle(
                            color: _colors.foreground,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...children,
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Lightweight root displayed while the app waits for its persisted data.
class StartupLoadingApp extends StatefulWidget {
  const StartupLoadingApp({super.key});

  @override
  State<StartupLoadingApp> createState() => _StartupLoadingAppState();
}

class _StartupLoadingAppState extends State<StartupLoadingApp> {
  /// On a healthy device this screen lasts well under a second, so the
  /// "waiting for storage" line would only ever flash. Keep it invisible
  /// (but laid out, so nothing shifts) and fade it in once the wait has
  /// gone on long enough to actually be a wait.
  static const _textDelay = Duration(milliseconds: 1500);

  bool _showText = false;
  Timer? _textTimer;

  @override
  void initState() {
    super.initState();
    _textTimer = Timer(_textDelay, () {
      if (mounted) setState(() => _showText = true);
    });
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StartupScaffold(
      animatedLogo: true,
      childrenBuilder: (colors) => [
        AnimatedOpacity(
          opacity: _showText ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              _startupString(AppLocale.startupLoading),
              textAlign: TextAlign.center,
              // Same voice as the splash's status line: the app font (Anta),
              // small and dimmed. GoogleFonts falls back gracefully for the
              // first frames if the font isn't warmed up yet.
              style: GoogleFonts.anta(
                color: colors.foreground.withValues(alpha: 0.6),
                fontSize: 17,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the configured user-data volume never appeared. Without this the
/// failure was swallowed by the catch-alls in `main()` and the app booted onto
/// an empty database, looking freshly installed.
class StartupStorageErrorApp extends StatelessWidget {
  const StartupStorageErrorApp({
    super.key,
    required this.storagePath,
    required this.onRetry,
    required this.onUseDefault,
  });

  final String? storagePath;
  final VoidCallback onRetry;
  final VoidCallback onUseDefault;

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      onRetry();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape) {
      onUseDefault();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return _StartupScaffold(
      onKeyEvent: _handleKey,
      childrenBuilder: (colors) => [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _startupString(AppLocale.startupStorageUnavailable),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.foreground.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              if (storagePath != null && storagePath!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  storagePath!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.foreground.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: onRetry,
                    child: Text(_startupString(AppLocale.startupStorageRetry)),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: onUseDefault,
                    child: Text(
                      _startupString(AppLocale.startupStorageUseDefault),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resolves the user-data location once, up front, while the loading screen is
/// on screen.
///
/// [ConfigService.getUserDataPath] has a dozen call sites; before this, each
/// one could serially block for the full cold-boot timeout. Doing it here means
/// the wait happens exactly once and its failure is visible to the user
/// instead of being degraded into an empty library by downstream catch-alls.
Future<void> _awaitUserDataStorage() async {
  while (!await ConfigService.ensureUserDataStorageReady()) {
    final decision = Completer<void>();
    var useDefault = false;
    runApp(
      StartupStorageErrorApp(
        storagePath: ConfigService.unavailableStoragePath,
        onRetry: () {
          ConfigService.resetStorageAvailability();
          if (!decision.isCompleted) decision.complete();
        },
        onUseDefault: () {
          useDefault = true;
          if (!decision.isCompleted) decision.complete();
        },
      ),
    );
    await decision.future;
    runApp(const StartupLoadingApp());
    if (useDefault) {
      ConfigService.continueWithDefaultUserDataPath();
      return;
    }
  }
}

@pragma('vm:entry-point')
Future<void> subDisplay() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('--- [SECONDARY ENGINE] subDisplay signal received ---');

  // The secondary display runs in its own engine/isolate, so it must set up
  // localization independently — otherwise AppLocale.getString() falls back to
  // raw keys here. Mirror the persisted-language init done in main().
  String initLang = 'en';
  // The main engine only pushes the theme name once it has state to share, so
  // without this the display would open on the brightness fallback (black)
  // even for a user on a light theme. Read it from the same config row.
  String? initThemeName;
  try {
    final rawConfig = await ConfigRepository.getUserConfig();
    if (rawConfig != null && rawConfig['app_language'] != null) {
      initLang = rawConfig['app_language'].toString();
    }
    initThemeName = rawConfig?['theme_name']?.toString();
  } catch (e) {
    debugPrint('Secondary display could not load saved config: $e');
  }
  await FlutterLocalization.instance.ensureInitialized();
  FlutterLocalization.instance.init(
    mapLocales: [
      MapLocale('en', AppLocale.en),
      MapLocale('es', AppLocale.es),
      MapLocale('pt', AppLocale.pt),
      MapLocale('ru', AppLocale.ru),
      MapLocale('zh', AppLocale.zh),
      MapLocale('zh_Hant', AppLocale.zhHant),
      MapLocale('fr', AppLocale.fr),
      MapLocale('de', AppLocale.de),
      MapLocale('it', AppLocale.it),
      MapLocale('id', AppLocale.id),
      MapLocale('ja', AppLocale.ja),
      MapLocale('ko', AppLocale.ko),
    ],
    initLanguageCode: initLang.isNotEmpty ? initLang : 'en',
  );

  runApp(SecondaryScreen(initialThemeName: initThemeName));
}

/// Provides MaterialLocalizations as a fallback for locales that Flutter's
/// global delegates do not support (e.g. zh_Hant). This prevents TextField
/// and other Material widgets from crashing when MaterialLocalizations.of
/// returns null.
class FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<MaterialLocalizations> old,
  ) => false;
}

class MyApp extends StatefulWidget {
  final FileProvider fileProvider;
  final AuthService authService;
  final SqliteConfigProvider sqliteConfigProvider;
  final SqliteDatabaseProvider sqliteDatabaseProvider;
  final NeoSyncService neoSyncService;
  final NeoSyncProvider neoSyncProvider;

  /// Built in `main()` with the saved theme already resolved, so the first
  /// frame paints in the user's theme rather than the brightness fallback.
  final ThemeProvider themeProvider;

  const MyApp({
    super.key,
    required this.fileProvider,
    required this.authService,
    required this.sqliteConfigProvider,
    required this.sqliteDatabaseProvider,
    required this.neoSyncService,
    required this.neoSyncProvider,
    required this.themeProvider,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _locale = FlutterLocalization.instance.currentLocale;
    FlutterLocalization.instance.onTranslatedLanguage = (Locale? locale) {
      if (mounted) setState(() => _locale = locale);
    };
    // Once the main UI has painted its first frame, tell the secondary display
    // the app is ready so it can slide the app dock into place (rather than
    // showing it fully-formed while the app is still cold-starting).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.sqliteConfigProvider.markAppReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => MenuAppProvider()),
        ChangeNotifierProvider.value(value: widget.sqliteConfigProvider),
        ChangeNotifierProvider.value(value: widget.sqliteDatabaseProvider),
        ChangeNotifierProvider.value(value: widget.fileProvider),
        ChangeNotifierProvider.value(value: widget.authService),
        ChangeNotifierProvider.value(value: widget.neoSyncService),
        ChangeNotifierProvider.value(value: widget.neoSyncProvider),
        ChangeNotifierProvider.value(value: SyncManager.instance),
        ChangeNotifierProvider(create: (context) => BillingService()),
        ChangeNotifierProvider(create: (context) => NotificationService()),
        ChangeNotifierProvider.value(value: widget.themeProvider),
        ChangeNotifierProvider(create: (context) => ScrapingProvider()),
        ChangeNotifierProvider(
          // Eager (not lazy): auto-login must run at startup so RA is connected
          // regardless of which screen is shown first. Otherwise launching a
          // game straight from the systems/recent screen (which never reads the
          // provider) would find RA disconnected and skip the secondary panel.
          lazy: false,
          create: (context) => RetroAchievementsProvider()..initialize(),
        ),
        ChangeNotifierProvider(create: (context) => SystemBackgroundProvider()),
        ChangeNotifierProvider(
          // Eager: the theme manifest is a network fetch, and during first-run
          // setup the wizard's art-pack step is the ONLY consumer of this
          // provider. A lazy create would not start loadThemes() until that
          // final step renders, leaving `themes` empty if the user advances
          // before the fetch resolves — the art pack then silently fails to
          // apply. Starting at launch gives the fetch the whole wizard to
          // complete.
          lazy: false,
          create: (context) => NeoAssetsProvider()..init(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return ScreenUtilInit(
            designSize: const Size(640, 480),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, child) {
              return FocusTraversalGroup(
                policy: NoFocusTraversalPolicy(),
                child: Shortcuts(
                  shortcuts: {
                    LogicalKeySet(
                      LogicalKeyboardKey.alt,
                      LogicalKeyboardKey.enter,
                    ): const ToggleFullscreenIntent(),
                  },
                  child: Actions(
                    actions: {ToggleFullscreenIntent: ToggleFullscreenAction()},
                    child: MaterialApp(
                      navigatorKey: rootNavigatorKey,
                      debugShowCheckedModeBanner: false,
                      title: 'NeoStation',
                      locale: _locale,
                      localizationsDelegates: [
                        const FallbackMaterialLocalizationsDelegate(),
                        ...FlutterLocalization.instance.localizationsDelegates,
                      ],
                      supportedLocales:
                          FlutterLocalization.instance.supportedLocales,
                      scrollBehavior: CustomScrollBehavior(),
                      showPerformanceOverlay: false,
                      checkerboardRasterCacheImages: false,
                      checkerboardOffscreenLayers: false,
                      showSemanticsDebugger: false,
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: MediaQuery.of(context).textScaler.clamp(
                              minScaleFactor: 0.6,
                              maxScaleFactor: 1.4,
                            ),
                          ),
                          child: child!,
                        );
                      },
                      theme: themeProvider.currentTheme.copyWith(
                        textTheme: GoogleFonts.antaTextTheme(
                          themeProvider.currentTheme.textTheme,
                        ),
                        iconTheme: const IconThemeData(fill: 1.0),
                        visualDensity: VisualDensity.adaptivePlatformDensity,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        pageTransitionsTheme: PageTransitionsTheme(
                          builders: {
                            TargetPlatform.android:
                                FadeUpwardsPageTransitionsBuilder(),
                            TargetPlatform.iOS:
                                FadeUpwardsPageTransitionsBuilder(),
                            TargetPlatform.windows:
                                FadeUpwardsPageTransitionsBuilder(),
                            TargetPlatform.macOS:
                                FadeUpwardsPageTransitionsBuilder(),
                            TargetPlatform.linux:
                                FadeUpwardsPageTransitionsBuilder(),
                          },
                        ),
                      ),
                      home: PermissionCheckWrapper(
                        child: AppLifecycleHandler(child: MainScreen()),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:neostation/services/logger_service.dart';
import '../services/notification_service.dart';
import '../services/neosync/auth_service.dart';
import '../sync/sync_manager.dart';
import '../sync/providers/neo_sync_adapter.dart';
import '../widgets/plan_welcome_modal.dart';
import '../widgets/plan_farewell_modal.dart';
import '../services/game_service.dart';
import '../services/music_player_service.dart';
import '../providers/sqlite_config_provider.dart';
import 'package:provider/provider.dart';

/// Widget that detects when the app returns to the foreground and reactivates the gamepad
class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({super.key, required this.child});

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  String? _lastKnownPlan;
  AppLifecycleListener? _exitListener;

  static final _log = LoggerService.instance;

  /// Determines the level of a plan (higher number = better plan)
  int _getPlanLevel(String planName) {
    switch (planName.toLowerCase()) {
      case 'free':
        return 0;
      case 'micro':
        return 1;
      case 'mini':
        return 2;
      case 'mega':
        return 3;
      case 'ultra':
        return 4;
      default:
        return 0;
    }
  }

  /// Determines whether the plan change is an upgrade or downgrade
  bool _isUpgrade(String oldPlan, String newPlan) {
    return _getPlanLevel(newPlan) > _getPlanLevel(oldPlan);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Register exit listener to clean up native resources (SoLoud audio threads)
    // so the process exits cleanly when the window is closed.
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        try {
          MusicPlayerService().dispose();
        } catch (_) {}
        return AppExitResponse.exit;
      },
    );

    // A HOME launcher is not paused on screen-off, so lifecycle `paused` never
    // fires on lock. Bridge the native screen on/off signal to the websocket:
    // suspend it while locked, reconnect on wake (music/audio is handled in
    // GameService's channel handler). Screen-on only fires here when NeoStation
    // is foreground (gated on !isGameLaunched at the call site).
    GameService.onScreenStateChanged = (screenOn) {
      if (!mounted) return;
      final notificationService = Provider.of<NotificationService>(
        context,
        listen: false,
      );
      if (screenOn) {
        notificationService.connect().catchError((error) {
          _log.e('Failed to reconnect notifications on screen-on: $error');
        });
      } else {
        notificationService.suspend();
      }
    };
    // Initialize with current plan after a delay to ensure auth is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait a bit more to ensure auth service is fully loaded
      await Future.delayed(Duration(milliseconds: 500));
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.isLoggedIn) {
        _lastKnownPlan = authService.currentUser?.plan;
      }
    });
  }

  @override
  void dispose() {
    _exitListener?.dispose();
    GameService.onScreenStateChanged = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      await GameService.handleAppResumed();

      if (!mounted) return;

      // Re-apply secondary display preference after display reconnection.
      if (Platform.isAndroid) {
        final configProvider = Provider.of<SqliteConfigProvider>(
          context,
          listen: false,
        );
        configProvider.reapplySecondaryDisplay();
        // Re-push accessibility (Screen Return) state to the secondary display:
        // the user may have just enabled it in system Settings (e.g. via the
        // in-game launcher's nudge), which controls the screenshot button and
        // the launcher's warning badge.
        // ignore: unawaited_futures
        configProvider.refreshSecondaryScreenshotAccess();
      }

      final notificationService = Provider.of<NotificationService>(
        context,
        listen: false,
      );
      notificationService.connect().catchError((error) {
        _log.e('Failed to reconnect notifications on app resume: $error');
      });

      MusicPlayerService().appResumed();

      await _checkForDataUpdates();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!mounted) return;
      Provider.of<NotificationService>(context, listen: false).suspend();
      MusicPlayerService().appPaused();
    }
  }

  Future<void> _checkForDataUpdates() async {
    final syncManager = Provider.of<SyncManager>(context, listen: false);
    final syncProvider = syncManager.active;

    // Only check if we have an authenticated provider
    if (syncProvider == null || !syncProvider.isAuthenticated) {
      return;
    }

    // Plan tracking is NeoSync-specific; gate behind provider id.
    if (syncProvider.providerId != NeoSyncAdapter.kProviderId) {
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);

    // Only check if the user is logged in
    if (!authService.isLoggedIn) {
      return;
    }

    try {
      // Check whether the profile changed (possible plan upgrade)
      final profileResult = await authService.getProfile();
      if (profileResult['success'] == true) {
        final currentUser = authService.currentUser;
        final currentPlan = currentUser?.plan;

        // Additional check: verify authentication by attempting a simple API call
        try {
          final quota = await syncProvider.getQuota();
          if (quota == null) {
            _log.e('NeoSync authentication failed');
          }
        } catch (e) {
          _log.e('Error refreshing sync data: $e');
          // Silently handle authentication errors to prevent unauthorized API calls
        }

        // If _lastKnownPlan is null, initialize it with the current plan
        if (_lastKnownPlan == null && currentPlan != null) {
          _lastKnownPlan = currentPlan;

          return; // Do not show modal on first initialization
        }

        // Detect plan change and show appropriate modal
        if (_lastKnownPlan != null &&
            currentPlan != null &&
            _lastKnownPlan != currentPlan) {
          final isUpgrade = _isUpgrade(_lastKnownPlan!, currentPlan);

          // Delay to ensure the UI updates first
          Future.delayed(Duration(milliseconds: 1000), () {
            if (mounted) {
              if (isUpgrade) {
                // Show welcome modal for upgrades
                PlanWelcomeModal.show(context, currentPlan);
              } else {
                // Show farewell modal for downgrades
                PlanFarewellModal.show(context, _lastKnownPlan!, currentPlan);
              }
            }
          });
        }

        // Update the known plan
        _lastKnownPlan = currentPlan;
      }
    } catch (e) {
      _log.e('Error checking for data updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/sqlite_config_provider.dart';
import 'setup_wizard.dart';

/// Widget that checks the initial configuration and shows the wizard if necessary
class PermissionCheckWrapper extends StatefulWidget {
  final Widget child;

  static const String setupCompletedKey = 'setup_completed_prefs';

  const PermissionCheckWrapper({super.key, required this.child});

  @override
  State<PermissionCheckWrapper> createState() => _PermissionCheckWrapperState();
}

class _PermissionCheckWrapperState extends State<PermissionCheckWrapper> {
  bool _needsSetup = false;
  bool _isChecking = true;

  static final _log = LoggerService.instance;

  @override
  void initState() {
    super.initState();

    // Check whether initial configuration is needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialSetup();
    });
  }

  static const String setupCompletedKey = 'setup_completed_prefs';

  Future<void> _checkInitialSetup() async {
    try {
      // Fast-path: SharedPreferences flag survives SD-card unavailability and
      // early-launcher boot races. If set, skip the wizard unconditionally.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PermissionCheckWrapper.setupCompletedKey) == true) {
        _pushWizardActive(false);
        setState(() {
          _needsSetup = false;
          _isChecking = false;
        });
        return;
      }

      if (!mounted) return;
      final configProvider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );

      if (!configProvider.initialized) {
        await configProvider.initialize();
      }

      final hasRomFolder = configProvider.config.romFolder?.isNotEmpty == true;
      final setupCompleted = configProvider.config.setupCompleted;

      if (hasRomFolder || setupCompleted) {
        // Backfill the SharedPreferences flag for existing users upgrading.
        await prefs.setBool(PermissionCheckWrapper.setupCompletedKey, true);
        _pushWizardActive(false);
        setState(() {
          _needsSetup = false;
          _isChecking = false;
        });
      } else {
        _pushWizardActive(true);
        setState(() {
          _needsSetup = true;
          _isChecking = false;
        });
      }
    } catch (e) {
      _log.e('Error checking initial setup: $e');
      _pushWizardActive(false);
      setState(() {
        _needsSetup = false;
        _isChecking = false;
      });
    }
  }

  /// Mirrors "the wizard is on screen" to the secondary display, which parks
  /// its app dock and launcher while setup runs. Pushed from here — the single
  /// place that decides whether the wizard shows — so a normal boot also clears
  /// a flag left behind by a run that was killed mid-wizard.
  void _pushWizardActive(bool active) {
    if (!mounted) return;
    Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    ).setSetupWizardActive(active);
  }

  void _completeSetup() async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    await configProvider.completeSetup();

    // Setup is done — let the secondary display bring in the dock/launcher.
    configProvider.setSetupWizardActive(false);

    // Persist flag to SharedPreferences so the wizard is never shown again
    // even if the SQLite DB is temporarily inaccessible (e.g. SD card not ready).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(setupCompletedKey, true);

    setState(() {
      _needsSetup = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // Show loading while checking
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needsSetup) {
      // Show configuration wizard
      return SetupWizard(onComplete: _completeSetup);
    }

    // Show the normal app
    return widget.child;
  }
}

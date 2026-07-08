import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/user_data_location_service.dart';
import 'package:neostation/services/screenshot_service.dart';
import 'package:neostation/providers/palette_provider.dart';
import '../providers/sqlite_config_provider.dart';
import '../utils/gamepad_nav.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import '../widgets/tv_directory_picker.dart';
import '../widgets/folder_not_empty_dialog.dart';
import '../models/secondary_display_state.dart';

/// Initial configuration wizard for the first time the app is opened
class SetupWizard extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupWizard({super.key, required this.onComplete});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard>
    with WidgetsBindingObserver {
  int _currentStep = 0;
  bool _isSelectingFolder = false;
  bool _isSelectingUserDataFolder = false;
  String? _selectedFolder;
  String? _selectedUserDataPath;
  SecondaryDisplayState? _secondaryDisplayState;

  /// Whether All-Files (storage) access is currently granted.
  bool _storageGranted = false;

  /// Whether the screenshot/return accessibility service is currently granted.
  /// Both are re-checked whenever the app resumes (the user grants them in
  /// system Settings, so we can't observe the change synchronously).
  bool _accessibilityGranted = false;

  /// Whether a secondary display is present. The accessibility (Screen Return)
  /// grant only makes sense on dual-screen devices, so we hide it otherwise.
  bool _hasSecondaryDisplay = false;

  /// Whether the accessibility grant should be offered at all.
  bool get _needsAccessibility => Platform.isAndroid && _hasSecondaryDisplay;

  /// Whether the accessibility requirement is satisfied — either it's granted,
  /// or it doesn't apply on this device.
  bool get _accessibilityDone => !_needsAccessibility || _accessibilityGranted;

  static final _log = LoggerService.instance;

  GamepadNavigation? _gamepadNav;

  // Step indices. Android has two extra steps (Permissions + Accessibility)
  // that don't exist on desktop; the getters resolve to -1 there so a
  // comparison against a real (>= 0) step never matches.
  //   Android: 0=UserData, 1=Permissions, 2=Folder, 3=Scanning
  //   Desktop: 0=UserData, 1=Folder, 2=Scanning
  // The Permissions step covers both All-Files access and the accessibility
  // (Screen Return) service.
  int get _stepUserData => 0;
  int get _stepPermissions => Platform.isAndroid ? 1 : -1;
  int get _stepFolder => Platform.isAndroid ? 2 : 1;
  int get _stepScanning => Platform.isAndroid ? 3 : 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSteps();
    _initGamepad();
    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
      _hasSecondaryDisplay =
          _secondaryDisplayState!.value?.isSecondaryActive ?? false;
      _secondaryDisplayState!.addListener(_onSecondaryStateChanged);
      _refreshPermissionStates();
    }
  }

  /// Keeps [_hasSecondaryDisplay] in sync so the accessibility row appears the
  /// moment a secondary display reports in (it may connect after the wizard
  /// first builds).
  void _onSecondaryStateChanged() {
    final has = _secondaryDisplayState?.value?.isSecondaryActive ?? false;
    if (has != _hasSecondaryDisplay && mounted) {
      setState(() => _hasSecondaryDisplay = has);
    }
  }

  /// Re-polls both permission states (storage + accessibility). Called on
  /// resume so the Permissions step reflects grants the user just made in
  /// system Settings.
  Future<void> _refreshPermissionStates() async {
    final storage = await PermissionService.hasAllFilesAccess();
    final access = await ScreenshotService.isAccessEnabled();
    if (mounted &&
        (storage != _storageGranted || access != _accessibilityGranted)) {
      setState(() {
        _storageGranted = storage;
        _accessibilityGranted = access;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshPermissionStates();
      // The gamepad was deactivated before we sent the user to Settings; bring
      // it back now that we have focus again on the Permissions step.
      if (_currentStep == _stepPermissions) _gamepadNav?.activate();
    }
  }

  void _initGamepad() {
    _gamepadNav = GamepadNavigation(
      onSelectItem: () {
        if (_isSelectingFolder || _isSelectingUserDataFolder) return;

        if (_currentStep == _stepScanning) {
          // Last step: A finishes when scan is done.
          final provider = Provider.of<SqliteConfigProvider>(
            context,
            listen: false,
          );
          if (provider.scanCompleted) _finishSetup();
        } else {
          _handleMainAction();
        }
      },
      onBack: () {
        _handleSkip();
      },
    );
    _gamepadNav?.initialize();
    _gamepadNav?.activate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _secondaryDisplayState?.removeListener(_onSecondaryStateChanged);
    _gamepadNav?.dispose();
    // Shared singleton — never dispose the instance.
    super.dispose();
  }

  void _updateSecondaryScreen(int bgColor, bool isOled) {
    if (_secondaryDisplayState == null) return;
    _secondaryDisplayState!.updateState(
      systemName: AppLocale.welcomeNeoStation.getString(context),
      useFluidShader: true,
      backgroundColor: bgColor,
      isOled: isOled,
      isGameSelected: false,
      clearFanart: true,
      clearScreenshot: true,
      clearWheel: true,
      clearVideo: true,
      clearImageBytes: true,
      clearGameId: true,
    );
  }

  void _handleSkip() {
    // Permissions step: the accessibility grant is optional, so once storage
    // is granted the user can skip past it to folder selection.
    if (_currentStep == _stepPermissions &&
        _storageGranted &&
        _needsAccessibility &&
        !_accessibilityGranted) {
      setState(() => _currentStep = _stepFolder);
      return;
    }

    if (_currentStep == _stepFolder) {
      // Skip folder selection → Advance to Scanning step.
      setState(() => _currentStep = _stepScanning);

      // Start initial scan to detect available systems (e.g., Android apps).
      final provider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.scanSystems();
      });
    }
  }

  void _initializeSteps() {
    // Load the current user-data path for display in step 0.
    ConfigService.getUserDataPath().then((p) {
      if (mounted) setState(() => _selectedUserDataPath = p);
    });
  }

  // Step layout:
  // Android: 0=UserData, 1=Permissions, 2=FolderSelect, 3=Scanning (4 steps)
  // Desktop: 0=UserData, 1=FolderSelect, 2=Scanning (3 steps)
  int get _totalSteps => Platform.isAndroid ? 4 : 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<PaletteProvider>(context);
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final isOled = themeProvider.isOled;
    final bgColor = theme.scaffoldBackgroundColor;

    // Synchronize secondary screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSecondaryScreen(bgColor.toARGB32(), isOled);
    });

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Dynamic Background: Fluid Shader
          if (!isOled)
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final bg = Theme.of(context).scaffoldBackgroundColor;
                  return Container(decoration: BoxDecoration(color: bg));
                },
              ),
            ),

          // Contenido principal
          SafeArea(
            child: isLandscape
                ? _buildLandscapeLayout(theme)
                : _buildPortraitLayout(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(ThemeData theme) {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 600.w),
        padding: EdgeInsets.all(32.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(32.r),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/images/logo_transparent.png',
              width: 120.r,
              height: 120.r,
            ),
            SizedBox(height: 24.r),

            // Título
            Text(
              AppLocale.welcomeNeoStation.getString(context),
              style: TextStyle(
                fontSize: 28.r,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12.r),

            Text(
              AppLocale.letsGetSetup.getString(context),
              style: TextStyle(
                fontSize: 16.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 48.r),

            // Progress indicator
            _buildProgressIndicator(theme),

            SizedBox(height: 32.r),

            // Step content
            Expanded(child: _buildStepContent(theme)),

            SizedBox(height: 24.r),

            // Navigation buttons
            _buildNavigationButtons(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.all(16.r),
      child: Row(
        children: [
          // Left side: Logo and title
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.all(24.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  width: 1.r,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo_transparent.png',
                    width: 64.r,
                    height: 64.r,
                  ),
                  SizedBox(height: 12.r),

                  Text(
                    AppLocale.welcomeNeoStation.getString(context),
                    style: TextStyle(
                      fontSize: 14.r,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8.r),

                  Text(
                    AppLocale.letsGetSetup.getString(context),
                    style: TextStyle(
                      fontSize: 10.r,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 16.r),

                  // Progress indicator vertical
                  _buildVerticalProgressIndicator(theme),
                ],
              ),
            ),
          ),

          SizedBox(width: 16.r),

          // Right side: Content and navigation
          Expanded(
            flex: 3,
            child: Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.05),
                  width: 1.r,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 400.w),
                        child: _buildStepContent(theme),
                      ),
                    ),
                  ),

                  SizedBox(height: 8.r),

                  // Navigation buttons
                  _buildNavigationButtons(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalProgressIndicator(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_totalSteps, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Column(
          children: [
            Container(
              width: 24.r,
              height: 24.r,
              decoration: BoxDecoration(
                color: isCompleted || isCurrent
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted || isCurrent
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 2.r,
                ),
              ),
              child: Center(
                child: isCompleted
                    ? Icon(
                        Symbols.check_rounded,
                        color: Colors.white,
                        size: 14.r,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 10.r,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Colors.white
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                        ),
                      ),
              ),
            ),
            if (index < _totalSteps - 1)
              Container(
                width: 2.r,
                height: 18.r,
                color: isCompleted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildProgressIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Row(
          children: [
            Container(
              width: 40.r,
              height: 40.r,
              decoration: BoxDecoration(
                color: isCompleted || isCurrent
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted || isCurrent
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 2.r,
                ),
              ),
              child: Center(
                child: isCompleted
                    ? Icon(
                        Symbols.check_rounded,
                        color: Colors.white,
                        size: 24.r,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 18.r,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Colors.white
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                        ),
                      ),
              ),
            ),
            if (index < _totalSteps - 1)
              Container(
                width: 40.r,
                height: 2.r,
                color: isCompleted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    if (_currentStep == _stepUserData) {
      return _buildUserDataLocationStep(theme);
    }
    if (_currentStep == _stepPermissions) {
      return _buildPermissionStep(theme);
    }
    if (_currentStep == _stepFolder) {
      return _buildFolderSelectionStep(theme);
    }
    if (_currentStep == _stepScanning) {
      return _buildScanningStep(theme);
    }
    return Container();
  }

  Widget _buildUserDataLocationStep(ThemeData theme) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final iconSize = isLandscape ? 48.r : 80.r;
    final titleSize = isLandscape ? 14.r : 24.r;
    final textSize = isLandscape ? 10.r : 14.r;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.folder_special_rounded,
            size: iconSize,
            color: _selectedUserDataPath != null
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
          SizedBox(height: isLandscape ? 16.r : 24.r),

          Text(
            AppLocale.userDataLocation.getString(context),
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isLandscape ? 8.r : 16.r),

          Text(
            AppLocale.userDataLocationSubtitle.getString(context),
            style: TextStyle(
              fontSize: textSize,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),

          if (_selectedUserDataPath != null) ...[
            SizedBox(height: isLandscape ? 8.r : 16.r),
            Container(
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.folder_rounded,
                    size: 16.r,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: 8.r),
                  Expanded(
                    child: Text(
                      _selectedUserDataPath!,
                      style: TextStyle(
                        fontSize: 11.r,
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: isLandscape ? 12.r : 20.r),

          // "Change Location" inline button
          OutlinedButton(
            onPressed: _isSelectingUserDataFolder
                ? null
                : () => _selectUserDataLocationWizard(),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 10.r),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: _isSelectingUserDataFolder
                ? SizedBox(
                    width: 18.r,
                    height: 18.r,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.r,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Text(
                    AppLocale.selectUserDataFolder.getString(context),
                    style: TextStyle(
                      fontSize: textSize,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Opens a folder picker, saves the new user-data path, and reinitializes the DB.
  Future<void> _selectUserDataLocationWizard() async {
    setState(() => _isSelectingUserDataFolder = true);
    _gamepadNav?.deactivate();

    try {
      String? selected;

      if (Platform.isAndroid) {
        final isTV = await PermissionService.isTelevision();
        if (isTV) {
          if (mounted) selected = await TvDirectoryPicker.show(context);
        } else {
          // Regular Android: same SAF picker as ROM folder selection.
          // Convert content:// URI to real filesystem path for SQLite access.
          try {
            final uri = await PermissionService.requestFolderAccess();
            if (uri != null) {
              selected = UserDataLocationService.safUriToRealPath(
                uri.toString(),
              );
            }
          } on PlatformException catch (e) {
            if (e.code == 'PICKER_FAILED' && mounted) {
              selected = await TvDirectoryPicker.show(context);
            }
          }
        }
      } else {
        selected = await FilePicker.getDirectoryPath(
          dialogTitle: AppLocale.selectUserDataFolder.getString(context),
          initialDirectory: _selectedUserDataPath,
        );
      }

      if (selected == null || !mounted) return;

      // Normalize trailing separator.
      if (selected.endsWith(Platform.pathSeparator)) {
        selected = selected.substring(0, selected.length - 1);
      }

      if (selected == _selectedUserDataPath) return;

      // Warn if the chosen folder already contains files, so the user doesn't
      // unknowingly store NeoStation's data inside an existing library.
      final entryCount = await UserDataLocationService.countDirectoryEntries(
        selected,
      );
      if (!mounted) return;
      if (entryCount > 0) {
        final proceed = await FolderNotEmptyDialog.show(
          context,
          path: selected,
          itemCount: entryCount,
        );
        if (!proceed || !mounted) return;
      }

      await UserDataLocationService.setCustomPath(selected);

      // Reinitialize the DB at the new path (no data yet on first launch).
      if (!mounted) return;
      final configProvider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );
      await configProvider.reinitialize();

      if (mounted) setState(() => _selectedUserDataPath = selected);
    } catch (e) {
      _log.e('User data location selection failed in wizard: $e');
    } finally {
      if (mounted) setState(() => _isSelectingUserDataFolder = false);
      _gamepadNav?.activate();
    }
  }

  /// Combined permissions step: All-Files (storage) access plus the optional
  /// accessibility (Screen Return) service, each with a live granted/pending
  /// status. The main action button grants the next pending one, then advances.
  Widget _buildPermissionStep(ThemeData theme) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPermissionRow(
            theme,
            icon: Symbols.security_rounded,
            title: AppLocale.storagePermission.getString(context),
            description: AppLocale.storagePermissionDesc.getString(context),
            granted: _storageGranted,
            isLandscape: isLandscape,
          ),
          // Screen Return access only applies to dual-screen devices.
          if (_needsAccessibility) ...[
            SizedBox(height: isLandscape ? 12.r : 20.r),
            _buildPermissionRow(
              theme,
              icon: Symbols.settings_accessibility_rounded,
              title: AppLocale.screenReturnAccess.getString(context),
              description: AppLocale.screenReturnAccessDesc.getString(context),
              granted: _accessibilityGranted,
              isLandscape: isLandscape,
              hint: AppLocale.screenReturnAccessHint.getString(context),
            ),
          ],
        ],
      ),
    );
  }

  /// A single permission entry: leading semantic icon, title + description, and
  /// a trailing status indicator that turns into a green check once granted.
  Widget _buildPermissionRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required bool granted,
    required bool isLandscape,
    String? hint,
  }) {
    final iconSize = isLandscape ? 28.r : 40.r;
    final titleSize = isLandscape ? 13.r : 18.r;
    final textSize = isLandscape ? 9.r : 13.r;

    return Container(
      padding: EdgeInsets.all(isLandscape ? 12.r : 16.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha: 0.5)
              : theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: granted ? Colors.green : theme.colorScheme.primary,
          ),
          SizedBox(width: isLandscape ? 12.r : 16.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4.r),
                Text(
                  granted ? AppLocale.enabled.getString(context) : description,
                  style: TextStyle(
                    fontSize: textSize,
                    color: granted
                        ? Colors.green
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
                if (!granted && hint != null) ...[
                  SizedBox(height: 6.r),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: textSize,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: isLandscape ? 8.r : 12.r),
          Icon(
            granted
                ? Symbols.check_circle_rounded
                : Symbols.radio_button_unchecked_rounded,
            size: isLandscape ? 20.r : 26.r,
            color: granted
                ? Colors.green
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSelectionStep(ThemeData theme) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final iconSize = isLandscape ? 48.r : 80.r;
    final titleSize = isLandscape ? 14.r : 24.r;
    final textSize = isLandscape ? 10.r : 14.r;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.folder_open_rounded,
            size: iconSize,
            color: _selectedFolder != null
                ? Colors.green
                : theme.colorScheme.primary,
          ),
          SizedBox(height: isLandscape ? 16.r : 24.r),

          Text(
            AppLocale.selectRomFolder.getString(context),
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: isLandscape ? 8.r : 16.r),

          Text(
            _selectedFolder != null
                ? '${AppLocale.romFolderSelected.getString(context)}\n\n$_selectedFolder'
                : AppLocale.chooseRomFolderDesc.getString(context),
            style: TextStyle(
              fontSize: textSize,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildScanningStep(ThemeData theme) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final containerSize = isLandscape ? 48.r : 80.r;
    final iconSize = isLandscape ? 24.r : 48.r;
    final titleSize = isLandscape ? 16.r : 24.r;
    final textSize = isLandscape ? 12.r : 14.r;

    return Consumer<SqliteConfigProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Scanning icon
              Container(
                width: containerSize,
                height: containerSize,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(containerSize / 2),
                ),
                child: Center(
                  child: provider.scanCompleted
                      ? Icon(
                          Symbols.check_circle_rounded,
                          color: Colors.green,
                          size: iconSize,
                        )
                      : SizedBox(
                          width: iconSize,
                          height: iconSize,
                          child: CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                            strokeWidth: 3.r,
                          ),
                        ),
                ),
              ),
              SizedBox(height: isLandscape ? 4.r : 24.r),

              Text(
                provider.scanCompleted
                    ? AppLocale.setupComplete.getString(context)
                    : AppLocale.scanningRoms.getString(context),
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: isLandscape ? 4.r : 16.r),

              Text(
                provider.scanStatus.isNotEmpty
                    ? provider.scanStatus
                    : AppLocale.scanningSystemsRoms.getString(context),
                style: TextStyle(
                  fontSize: textSize,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),

              // Progress bar
              if (provider.totalSystemsToScan > 0 &&
                  !provider.scanCompleted) ...[
                SizedBox(height: isLandscape ? 4.r : 32.r),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: LinearProgressIndicator(
                    value: provider.scanProgress,
                    minHeight: 8.r,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.1,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                SizedBox(height: 8.r),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocale.ofSystems
                          .getString(context)
                          .replaceFirst(
                            '{scanned}',
                            provider.scannedSystemsCount.toString(),
                          )
                          .replaceFirst(
                            '{total}',
                            provider.totalSystemsToScan.toString(),
                          ),
                      style: TextStyle(
                        fontSize: textSize - 2.r,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      '${(provider.scanProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: textSize - 2.r,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],

              if (provider.scanCompleted) ...[
                SizedBox(height: isLandscape ? 4.r : 32.r),
                Container(
                  padding: EdgeInsets.all(isLandscape ? 12.r : 16.r),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                      width: 1.r,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.check_circle_rounded,
                        color: Colors.green,
                        size: isLandscape ? 20.r : 24.r,
                      ),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: Text(
                          '${AppLocale.foundSystemsWithGames.getString(context).replaceFirst('{count}', provider.detectedRealSystems.length.toString())}\n${AppLocale.tapFinishToStart.getString(context)}',
                          style: TextStyle(
                            fontSize: textSize,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationButtons(ThemeData theme) {
    // The last step is always the scanning step
    final isInScanningStep = _currentStep == _stepScanning;

    if (isInScanningStep) {
      return Consumer<SqliteConfigProvider>(
        builder: (context, provider, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Finish button only when scan completes
              ElevatedButton(
                onPressed: provider.scanCompleted ? () => _finishSetup() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.r,
                    vertical: 12.r,
                  ),
                  elevation: 4,
                  shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  disabledBackgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.3,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_A_button.png',
                      width: 20.r,
                      height: 20.r,
                      color: theme.colorScheme.onPrimary,
                    ),
                    SizedBox(width: 8.r),
                    Text(
                      AppLocale.finish.getString(context),
                      style: TextStyle(
                        fontSize: 14.r,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    // For other steps, use normal logic
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Skip button on the optional steps: the folder step, and the
        // permissions step once storage is granted (only accessibility, which
        // is optional, remains).
        if (Platform.isAndroid &&
            (_currentStep == _stepFolder ||
                (_currentStep == _stepPermissions &&
                    _storageGranted &&
                    _needsAccessibility &&
                    !_accessibilityGranted)))
          TextButton(
            onPressed: () => _handleSkip(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/gamepad/Xbox_B_button.png',
                  width: 20.r,
                  height: 20.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                SizedBox(width: 8.r),
                Text(
                  AppLocale.skipForNow.getString(context),
                  style: TextStyle(
                    fontSize: 12.r,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(width: 64.r),

        // Main action button
        ElevatedButton(
          onPressed: _isSelectingFolder ? null : () => _handleMainAction(),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: EdgeInsets.symmetric(horizontal: 20.r, vertical: 12.r),
            elevation: 4,
            shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            disabledBackgroundColor: theme.colorScheme.primary.withValues(
              alpha: 0.3,
            ),
          ),
          child: _isSelectingFolder
              ? SizedBox(
                  width: 20.r,
                  height: 20.r,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.r,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.onPrimary,
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_A_button.png',
                      width: 20.r,
                      height: 20.r,
                      color: theme.colorScheme.onPrimary,
                    ),
                    SizedBox(width: 8.r),
                    Text(
                      _getButtonText(),
                      style: TextStyle(
                        fontSize: 14.r,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _getButtonText() {
    if (_currentStep == _stepUserData) return AppLocale.next.getString(context);
    if (_currentStep == _stepPermissions) {
      // Grant the next pending permission; once both are satisfied, advance.
      if (!_storageGranted || !_accessibilityDone) {
        return AppLocale.grantAccess.getString(context);
      }
      return AppLocale.next.getString(context);
    }
    if (_currentStep == _stepFolder) {
      return AppLocale.selectFolder.getString(context);
    }
    return AppLocale.next.getString(context);
  }

  Future<void> _handleMainAction() async {
    // Step 0 (user data location): advance, then auto-skip the permissions step
    // if both permissions are already granted.
    if (_currentStep == _stepUserData) {
      setState(() => _currentStep = _currentStep + 1);
      if (Platform.isAndroid) {
        _refreshPermissionStates().then((_) {
          if (mounted &&
              _currentStep == _stepPermissions &&
              _storageGranted &&
              _accessibilityDone) {
            setState(() => _currentStep = _stepFolder);
          }
        });
      }
      return;
    }

    if (_currentStep == _stepPermissions) {
      await _handlePermissionAction();
      return;
    }

    if (_currentStep == _stepFolder) {
      await _selectFolder();
    }
  }

  /// Drives the combined permissions step: grants the next pending permission
  /// (storage first, then accessibility), or advances to folder once both are
  /// granted. Gamepad input is suspended around any trip to system Settings.
  Future<void> _handlePermissionAction() async {
    // Both satisfied → move on.
    if (_storageGranted && _accessibilityDone) {
      setState(() => _currentStep = _stepFolder);
      return;
    }

    // Deactivate gamepad before opening system settings to prevent key event
    // leakage when the app regains focus after the user grants the permission.
    _gamepadNav?.deactivate();
    try {
      if (!_storageGranted) {
        final success = await PermissionService.requestAllFilesAccess();
        if (success && mounted) {
          context.read<SqliteConfigProvider>().refreshAllFilesAccess();
          setState(() => _storageGranted = true);
        }
      } else {
        // Accessibility can't be granted in-app — send the user to system
        // Settings. We re-check on resume (didChangeAppLifecycleState) and
        // light up the green check when they come back with it enabled.
        await ScreenshotService.openAccessSettings();
      }
    } catch (e) {
      _log.e('Error requesting permissions: $e');
    } finally {
      // Drain any pending key events before re-enabling gamepad input.
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _gamepadNav?.activate();
    }
  }

  Future<void> _selectFolder() async {
    if (_currentStep != _stepFolder) return;

    // Guard: prevent re-entry and stop gamepad from intercepting picker events
    setState(() {
      _isSelectingFolder = true;
    });
    _gamepadNav?.deactivate();

    try {
      final configProvider = Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      );

      String? result;

      if (Platform.isAndroid) {
        final isTV = await PermissionService.isTelevision();
        if (isTV) {
          // Android TV / Google TV: always use custom browser (SAF picker is unreliable on TV)
          if (mounted) result = await TvDirectoryPicker.show(context);
        } else {
          try {
            final uri = await PermissionService.requestFolderAccess();
            result = uri?.toString();
          } on PlatformException catch (e) {
            if (e.code == 'PICKER_FAILED' && mounted) {
              result = await TvDirectoryPicker.show(context);
            }
          }
        }

        if (result != null && mounted) {
          await configProvider.addRomFolder(result, scan: false);
        }
      } else {
        await configProvider.selectRomFolder(scan: false);
        // Provider already called addRomFolder internally; read back the path
        result = configProvider.config.romFolder;
      }

      if (result != null && mounted) {
        setState(() {
          _selectedFolder = result;
          _isSelectingFolder = false;
          _currentStep++;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          configProvider.scanSystems();
        });
      } else if (mounted) {
        setState(() {
          _isSelectingFolder = false;
        });
      }
    } catch (e) {
      _log.e('Error selecting folder: $e');
      if (mounted) {
        setState(() {
          _isSelectingFolder = false;
        });
      }
    } finally {
      _gamepadNav?.activate();
    }
  }

  Future<void> _finishSetup() async {
    // Verificar que la configuración está guardada
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    final savedFolder = configProvider.config.romFolder;

    if (savedFolder == null || savedFolder.isEmpty) {
      _log.w('Warning: ROM folder not saved in config!');
    }

    // Forzar guardado de la configuración
    await configProvider.saveConfig();

    // Llamar al callback de completado
    widget.onComplete();
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/themes/app_themes.dart';
import 'package:provider/provider.dart';
import '../models/core_emulator_model.dart';
import '../models/standalone_emulator_model.dart';
import '../themes/corner_radii.dart';
import 'system_emulator_settings_dialog/models/emulator_list_item.dart';
import '../models/system_model.dart';
import '../providers/sqlite_config_provider.dart';
import '../providers/sqlite_database_provider.dart';
import '../repositories/system_repository.dart';
import '../repositories/emulator_repository.dart';
import '../services/config_service.dart';
import 'package:neostation/services/logger_service.dart';
import '../utils/gamepad_nav.dart';
import '../services/game_service.dart' show GamepadNavigationManager;
import '../utils/centered_scroll_controller.dart';
import 'package:path/path.dart' as path;

import 'custom_notification.dart';
import 'package:neostation/widgets/custom_toggle_switch.dart';
import '../widgets/shaders/shader_gif_widget.dart';
import '../utils/image_utils.dart';
import '../widgets/core_footer.dart';
import '../services/permission_service.dart';
import '../widgets/tv_directory_picker.dart';

part 'system_emulator_settings_dialog/gamepad_nav.dart';
part 'system_emulator_settings_dialog/row_builders.dart';
part 'system_emulator_settings_dialog/chrome.dart';
part 'system_emulator_settings_dialog/tabs.dart';

/// Steam-style dialog to configure emulators/cores for a system
class SystemEmulatorSettingsDialog extends StatefulWidget {
  final SystemModel system;

  const SystemEmulatorSettingsDialog({super.key, required this.system});

  @override
  State<SystemEmulatorSettingsDialog> createState() =>
      _SystemEmulatorSettingsDialogState();
}

class _SystemEmulatorSettingsDialogState
    extends State<SystemEmulatorSettingsDialog> {
  List<EmulatorListItem> _displayItems = []; // Grouped items for display
  int _totalEmulators = 0;
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedIndex = 0;
  late GamepadNavigation _gamepadNav; // Now includes keyboard on desktop
  late CenteredScrollController _centeredScrollController;
  late ScrollController _generalScrollController;

  static final _log = LoggerService.instance;

  // Tabs state
  int _currentTab = 0; // Default to General tab
  int _generalIndex = 0; // Index for General tab items
  int _appearanceIndex = 0; // Index for Appearance tab items
  // Emulators tab: 0 = default/core action, 1 = executable picker.
  int _emulatorActionIndex = 0;
  // 0: Prefer filename, 1: Hide ext, 2: (), 3: [], 4: Recursive?,
  // 5: Show subfolders
  late int _totalGeneralItems;
  late List<GlobalKey> _generalItemKeys;
  late List<GlobalKey> _appearanceItemKeys;

  late SystemModel _system;

  // Focus nodes for arrow key navigation blocking
  late final FocusNode _headerCloseButtonFocusNode;
  late final FocusNode _footerCloseButtonFocusNode;
  late List<FocusNode> _coreItemFocusNodes;
  late List<FocusNode> _setDefaultButtonFocusNodes;
  List<MenuController> _menuControllers = [];
  List<FocusNode> _menuFocusNodes = [];
  final Map<int, List<FocusNode>> _menuCoresFocusNodes =
      {}; // index -> list of FocusNodes for cores
  int _openMenuIndex = -1; // Index of the open MenuAnchor, -1 if none

  @override
  void initState() {
    super.initState();

    // Initialize focus nodes for arrow key navigation blocking
    _headerCloseButtonFocusNode = FocusNode(skipTraversal: true);
    _footerCloseButtonFocusNode = FocusNode(skipTraversal: true);
    _coreItemFocusNodes = [];
    _setDefaultButtonFocusNodes = [];

    // Initialize the centered scroll controller
    _centeredScrollController = CenteredScrollController(
      centerPosition: 0.5, // Center towards the top of the viewport
    );

    // Initialize local system state
    _system = widget.system;
    _totalGeneralItems =
        (_system.folderName == 'all' || _system.folderName == 'android')
        ? 4
        : 6;

    _generalScrollController = ScrollController();
    _generalItemKeys = List.generate(
      _totalGeneralItems,
      (index) => GlobalKey(
        debugLabel:
            'general_item_${_system.folderName}_${index}_${identityHashCode(this)}',
      ),
    );

    _appearanceItemKeys = List.generate(
      2,
      (index) => GlobalKey(
        debugLabel:
            'appearance_item_${_system.folderName}_${index}_${identityHashCode(this)}',
      ),
    );

    _loadCores();
    _initializeGamepad();
  }

  @override
  void dispose() {
    _cleanupGamepad();
    _centeredScrollController.dispose();
    _generalScrollController.dispose();
    // Dispose focus nodes
    _headerCloseButtonFocusNode.dispose();
    _footerCloseButtonFocusNode.dispose();
    for (final node in _coreItemFocusNodes) {
      node.dispose();
    }
    for (final node in _setDefaultButtonFocusNodes) {
      node.dispose();
    }
    for (final node in _menuFocusNodes) {
      node.dispose();
    }
    for (final nodesList in _menuCoresFocusNodes.values) {
      for (final node in nodesList) {
        node.dispose();
      }
    }
    super.dispose();
  }

  /// Bridge so `part`/`extension` files can trigger a rebuild — `State.setState`
  /// is `@protected` and can't be invoked from an extension.
  void rebuild(VoidCallback fn) => setState(fn);

  Future<void> _toggleRecursiveScan(bool value) async {
    setState(() {
      _system = _system.copyWith(recursiveScan: value);
    });

    // 1. Save to DB
    await SystemRepository.setRecursiveScan(widget.system.id!, value);

    // 2. Trigger automatic scan (Silent)
    try {
      // Ensure we use the updated recursiveScan flag for the scan
      final systemToScan = widget.system.copyWith(recursiveScan: value);

      if (!mounted) return;

      // Perform silent scan via provider
      final summary = await context
          .read<SqliteConfigProvider>()
          .rescanSystemSilent(systemToScan);

      // 3. Refresh current system's game list in the provider
      if (mounted) {
        // Refresh current system's game list
        context.read<SqliteDatabaseProvider>().loadGamesForSystem(
          systemToScan.folderName,
        );
      }

      if (mounted) {
        String message = 'Scan complete for ${widget.system.realName}';
        if (summary.hasChanges) {
          message += ': ';
          if (summary.added > 0) message += '${summary.added} added';
          if (summary.added > 0 && summary.removed > 0) message += ', ';
          if (summary.removed > 0) message += '${summary.removed} removed';
        } else {
          message += '. No changes found.';
        }

        AppNotification.showNotification(
          context,
          message,
          type: summary.hasChanges
              ? NotificationType.success
              : NotificationType.info,
          notificationId: 'system_scan_${widget.system.id}',
        );
      }
    } catch (e) {
      _log.e('Error during auto-scan: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorScanningSystem
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
          notificationId: 'system_scan_${widget.system.id}',
        );
      }
    }
  }

  Future<void> _togglePreferFileName(bool value) async {
    setState(() => _system = _system.copyWith(preferFileName: value));
    await SystemRepository.setPreferFileName(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      context.read<SqliteDatabaseProvider>().loadGamesForSystem(
        widget.system.folderName,
      );
      AppNotification.showNotification(
        context,
        value
            ? AppLocale.romFileNamesUsed.getString(context)
            : AppLocale.scrapedTitlesUsed.getString(context),
        type: NotificationType.info,
      );
    }
  }

  Future<void> _toggleSubfolderView(bool value) async {
    setState(() => _system = _system.copyWith(subfolderView: value));
    await SystemRepository.setSubfolderView(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      context.read<SqliteDatabaseProvider>().loadGamesForSystem(
        widget.system.folderName,
      );
      AppNotification.showNotification(
        context,
        (value
                ? AppLocale.subfolderViewEnabled
                : AppLocale.subfolderViewDisabled)
            .getString(context),
        type: NotificationType.info,
      );
    }
  }

  Future<void> _toggleHideExtension(bool value) async {
    setState(() => _system = _system.copyWith(hideExtension: value));
    await SystemRepository.setHideExtension(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      context.read<SqliteDatabaseProvider>().loadGamesForSystem(
        widget.system.folderName,
      );
      AppNotification.showNotification(
        context,
        (value ? AppLocale.gameExtensionsHidden : AppLocale.gameExtensionsShown)
            .getString(context),
        type: NotificationType.info,
      );
    }
  }

  Future<void> _toggleHideParentheses(bool value) async {
    setState(() => _system = _system.copyWith(hideParentheses: value));
    await SystemRepository.setHideParentheses(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      context.read<SqliteDatabaseProvider>().loadGamesForSystem(
        widget.system.folderName,
      );
      AppNotification.showNotification(
        context,
        (value ? AppLocale.parenthesesHidden : AppLocale.parenthesesShown)
            .getString(context),
        type: NotificationType.info,
      );
    }
  }

  Future<void> _toggleHideBrackets(bool value) async {
    setState(() => _system = _system.copyWith(hideBrackets: value));
    await SystemRepository.setHideBrackets(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      context.read<SqliteDatabaseProvider>().loadGamesForSystem(
        widget.system.folderName,
      );
      AppNotification.showNotification(
        context,
        (value ? AppLocale.bracketsHidden : AppLocale.bracketsShown).getString(
          context,
        ),
        type: NotificationType.info,
      );
    }
  }

  void _scrollToSelected({bool animate = true}) {
    _centeredScrollController.scrollToIndex(
      _selectedIndex,
      immediate: !animate,
    );
  }

  void _scrollToGeneralSelected() {
    final key = _generalItemKeys[_generalIndex];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scrollToAppearanceSelected() {
    final key = _appearanceItemKeys[_appearanceIndex];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _setSelectedAsDefault() {
    if (_totalEmulators == 0 || _selectedIndex >= _totalEmulators) return;

    final item = _displayItems[_selectedIndex];
    if (item is EmulatorCoreItem) {
      _setAsDefault(item.core);
    } else if (item is EmulatorStandaloneItem) {
      final isConfigured = Platform.isAndroid
          ? item.isInstalled
          : item.standalone.isConfigured;
      if (isConfigured) {
        _setStandaloneAsDefault(item.standalone);
      }
    } else if (item is EmulatorGroupedCoreItem) {
      // Check if disabled (using same logic as UI)
      final isDisabled = Platform.isAndroid
          ? !item.isInstalled
          : !item.retroArchConfigured;

      if (!isDisabled && _selectedIndex < _menuControllers.length) {
        _menuControllers[_selectedIndex].open();
      }
    }
  }

  void _closeDialog() {
    // Limpiar gamepad antes de cerrar
    if (_openMenuIndex != -1) {
      if (_openMenuIndex < _menuControllers.length) {
        _menuControllers[_openMenuIndex].close();
      }
      return;
    }
    _cleanupGamepad();
    Navigator.of(context).pop();
  }

  Future<void> _loadCores() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.system.id == null) {
        throw Exception('System ID is null');
      }

      // Fetch fresh system settings to ensure we have custom logos/settings
      try {
        final freshSystem = await SystemRepository.getSystemByFolderName(
          widget.system.folderName,
        );
        if (freshSystem != null) _system = freshSystem;
      } catch (e) {
        _log.w(
          'System not found in DB: ${widget.system.folderName}. Using passed model.',
        );
        _system = widget.system;
      }

      // Load both cores and standalone emulators
      final cores = await EmulatorRepository.getCoresBySystemId(
        widget.system.id!,
      );
      final standalonesData =
          await EmulatorRepository.getStandaloneEmulatorsBySystemId(
            widget.system.id!,
          );
      final standalones = standalonesData
          .map((e) => StandaloneEmulatorModel.fromMap(e))
          .toList();

      // Setup grouped items for display
      final displayItems = <EmulatorListItem>[];

      // Check if RetroArch is configured (for desktop platforms)
      bool retroArchConfigured = false;
      String? retroArchPath;
      if (!Platform.isAndroid) {
        try {
          final detectedEmus =
              await EmulatorRepository.getUserDetectedEmulators();
          if (detectedEmus.containsKey('RetroArch')) {
            retroArchConfigured = true;
            retroArchPath = detectedEmus['RetroArch']?.path;
          }
        } catch (e) {
          _log.e('Error checking RetroArch configuration: $e');
        }
      }

      // Group cores by variant (Package name on Android, generic on Desktop)
      final groupedCores = <String, List<CoreEmulatorModel>>{};
      for (final core in cores) {
        String groupKey;
        if (Platform.isAndroid) {
          groupKey = core.androidPackageName ?? 'com.retroarch';

          // Heuristic fallback if package name is missing but uniqueId exists
          if (core.androidPackageName == null ||
              core.androidPackageName!.isEmpty) {
            final uid = core.uniqueId;
            if (uid.contains('.ra64.')) {
              groupKey = 'com.retroarch.aarch64';
            } else if (uid.contains('.ra32.')) {
              groupKey = 'com.retroarch.ra32';
            } else if (uid.contains('.ra.')) {
              groupKey = 'com.retroarch';
            }
          }
        } else {
          groupKey = 'RetroArch'; // Unified on desktop
        }

        if (!groupedCores.containsKey(groupKey)) {
          groupedCores[groupKey] = [];
        }
        groupedCores[groupKey]!.add(core);
      }

      // 1. Add grouped RetroArch entries
      groupedCores.forEach((groupKey, groupCores) {
        String groupName = 'RetroArch';
        if (groupKey == 'com.retroarch.aarch64') {
          groupName = 'RetroArch 64';
        } else if (groupKey == 'com.retroarch.ra32') {
          groupName = 'RetroArch 32';
        } else if (groupKey == 'com.retroarch.a' ||
            groupKey == 'com.retroarch.plus') {
          groupName = 'RetroArch Plus';
        }

        // Check if ANY core in this group is installed (on Android)
        bool isInstalled = groupCores.any((c) => c.isInstalled);

        displayItems.add(
          EmulatorGroupedCoreItem(
            groupName: groupName,
            packageName: groupKey,
            cores: groupCores,
            isInstalled: isInstalled,
            retroArchConfigured: retroArchConfigured,
            retroArchPath: retroArchPath,
          ),
        );
      });

      // 2. Add Standalone emulators
      for (final standalone in standalones) {
        final isInstalled = await standalone.isInstalled;
        displayItems.add(
          EmulatorStandaloneItem(standalone, isInstalled: isInstalled),
        );
      }

      setState(() {
        _displayItems = displayItems;
        _totalEmulators = _displayItems.length; // Now strictly UI items

        // Find selected index based on default
        _selectedIndex = 0;

        // Strategy: find the item that corresponds to the default
        int foundIndex = -1;

        // We iterate _displayItems to find the match
        for (int i = 0; i < _displayItems.length; i++) {
          final item = _displayItems[i];

          if (item is EmulatorStandaloneItem) {
            if (item.standalone.isUserDefault == true) {
              foundIndex = i;
              break;
            }
          } else if (item is EmulatorGroupedCoreItem) {
            if (item.cores.any((c) => c.isDefault)) {
              foundIndex = i;
              break;
            }
          } else if (item is EmulatorCoreItem) {
            if (item.core.isDefault) {
              foundIndex = i;
              break;
            }
          }
        }

        if (foundIndex != -1) {
          _selectedIndex = foundIndex;
        } else if (_displayItems.isNotEmpty) {
          for (int i = 0; i < _displayItems.length; i++) {
            if (_displayItems[i] is! EmulatorHeaderItem) {
              _selectedIndex = i;
              break;
            }
          }
        }
      });

      // Update focus nodes for the new emulators list
      _updateFocusNodes();

      // Inicializar el controller después de cargar emulators
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centeredScrollController.initialize(
          context: context,
          initialIndex: _selectedIndex,
          totalItems: _totalEmulators,
        );
        // Actualizar el total de items después de inicializar
        _centeredScrollController.updateTotalItems(_totalEmulators);
      });
    } catch (e, stackTrace) {
      _log.e('ERROR loading cores: $e');
      _log.e('StackTrace: $stackTrace');

      setState(() {
        _errorMessage = 'Error loading cores: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Update focus nodes when cores list changes
  void _updateFocusNodes() {
    // Dispose old focus nodes
    for (final node in _coreItemFocusNodes) {
      node.dispose();
    }
    for (final node in _setDefaultButtonFocusNodes) {
      node.dispose();
    }

    // Create new focus nodes for both cores and standalones
    _coreItemFocusNodes = List.generate(
      _totalEmulators,
      (_) => FocusNode(skipTraversal: true),
    );
    _setDefaultButtonFocusNodes = List.generate(
      _totalEmulators,
      (_) => FocusNode(skipTraversal: true),
    );

    // Initialize MenuControllers and FocusNodes
    _menuControllers = List.generate(_totalEmulators, (_) => MenuController());
    _menuFocusNodes = List.generate(_totalEmulators, (_) => FocusNode());

    // Dispose and clear core focus nodes
    for (final nodesList in _menuCoresFocusNodes.values) {
      for (final node in nodesList) {
        node.dispose();
      }
    }
    _menuCoresFocusNodes.clear();

    // Create new focus nodes for cores within menu
    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      if (item is EmulatorGroupedCoreItem) {
        _menuCoresFocusNodes[i] = List.generate(
          item.cores.length,
          (_) => FocusNode(),
        );
      }
    }
  }

  Future<void> _setAsDefault(CoreEmulatorModel core) async {
    try {
      if (widget.system.id == null) {
        throw Exception('System ID is null');
      }

      await EmulatorRepository.setDefaultCore(
        widget.system.id!,
        core.uniqueId,
        core.osId,
      );

      // Reload cores to refresh UI and grouping
      await _loadCores();

      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.coreSetAsDefault
              .getString(context)
              .replaceFirst('{name}', core.name),
          type: NotificationType.success,
        );
      }
    } catch (e, stackTrace) {
      _log.e('Error setting default core: $e');
      _log.e('   Stack trace: $stackTrace');

      // Show user-friendly error message
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorSettingDefault
              .getString(context)
              .replaceFirst('{name}', core.name),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _setStandaloneAsDefault(
    StandaloneEmulatorModel standalone,
  ) async {
    try {
      if (widget.system.id == null) {
        throw Exception('System ID is null');
      }

      await EmulatorRepository.setDefaultStandaloneEmulator(
        widget.system.id!,
        standalone.uniqueIdentifier,
      );

      // Reload cores to refresh UI and grouping
      await _loadCores();

      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.coreSetAsDefault
              .getString(context)
              .replaceFirst('{name}', standalone.name),
          type: NotificationType.success,
        );
      }
    } catch (e, stackTrace) {
      _log.e('Error setting default standalone emulator: $e');
      _log.e('   Stack trace: $stackTrace');

      // Show user-friendly error message
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorSettingDefault
              .getString(context)
              .replaceFirst('{name}', standalone.name),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _configureStandalonePath(
    StandaloneEmulatorModel standalone,
  ) async {
    try {
      // Determine executable extension based on platform
      final extension = Platform.isWindows ? 'exe' : null;

      final selectedPath = Platform.isLinux
          ? await TvDirectoryPicker.showExecutablePicker(context)
          : (await FilePicker.pickFiles(
              dialogTitle: AppLocale.selectEmulatorExecutable
                  .getString(context)
                  .replaceFirst('{name}', standalone.name),
              type: extension != null ? FileType.custom : FileType.any,
              allowedExtensions: extension != null ? [extension] : null,
              lockParentWindow: true,
            ))?.files.firstOrNull?.path;

      if (selectedPath == null) return;

      // Verify file exists
      bool exists = false;
      if (Platform.isMacOS && selectedPath.endsWith('.app')) {
        exists = await Directory(selectedPath).exists();
      } else {
        exists = await File(selectedPath).exists();
      }

      if (!exists) {
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.selectedFileNotExist.getString(context),
            type: NotificationType.error,
          );
        }
        return;
      }

      // Save path to database
      await EmulatorRepository.setStandaloneEmulatorPath(
        standalone.uniqueIdentifier,
        Platform.isLinux
            ? TvDirectoryPicker.persistedExecutablePath(selectedPath)
            : selectedPath,
      );

      // Reload the full dialog to update UI (same as RetroArch)
      await _loadCores();

      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.emulatorPathConfigured
              .getString(context)
              .replaceFirst('{name}', standalone.name),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorConfiguringPath
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  /// Configure RetroArch executable path on desktop platforms
  Future<void> _configureRetroArchPath() async {
    try {
      final selectedPath = Platform.isLinux
          ? await TvDirectoryPicker.showExecutablePicker(context)
          : (await FilePicker.pickFiles(
              type: Platform.isWindows ? FileType.custom : FileType.any,
              allowedExtensions: Platform.isWindows ? ['exe'] : null,
              dialogTitle: AppLocale.selectRetroArchExe.getString(context),
            ))?.files.firstOrNull?.path;

      if (selectedPath == null) return;

      // Verify the file exists
      bool exists = false;
      if (Platform.isMacOS && selectedPath.endsWith('.app')) {
        exists = await Directory(selectedPath).exists();
      } else {
        exists = await File(selectedPath).exists();
      }

      if (!exists) {
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.selectedFileNotExist.getString(context),
            type: NotificationType.error,
          );
        }
        return;
      }

      // Save RetroArch path
      await EmulatorRepository.saveDetectedEmulatorPath(
        emulatorName: 'RetroArch',
        emulatorPath: Platform.isLinux
            ? TvDirectoryPicker.persistedExecutablePath(selectedPath)
            : selectedPath,
      );

      // Refresh the dialog to update UI
      await _loadCores();

      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.retroArchPathConfigured.getString(context),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorConfiguringRetroArchPath
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 16.r),
      child: Container(
        constraints: BoxConstraints(maxWidth: 640.r, maxHeight: 480.r),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.5),
              blurRadius: 10.r,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildTabsHeader(),
            Expanded(
              child: _currentTab == 0
                  ? _buildGeneralTab()
                  : _currentTab == 1
                  ? (_isLoading
                        ? _buildLoadingState()
                        : _errorMessage != null
                        ? _buildErrorState()
                        : _buildEmulatorsTab())
                  : _buildAppearanceTab(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}

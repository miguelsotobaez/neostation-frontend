import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import '../models/core_emulator_model.dart';
import '../models/standalone_emulator_model.dart';
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
  // 0: Prefer filename, 1: Hide ext, 2: (), 3: [], 4: Logo, 5: Recursive?
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
        ? 5
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

    if (mounted) {
      AppNotification.showNotification(
        context,
        (value
                ? AppLocale.recursiveScanEnabled
                : AppLocale.recursiveScanDisabled)
            .getString(context)
            .replaceFirst('{name}', widget.system.realName),
        type: NotificationType.info,
        notificationId: 'system_scan_${widget.system.id}',
      );
    }

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

  Future<void> _toggleHideLogo(bool value) async {
    setState(() => _system = _system.copyWith(hideLogo: value));
    await SystemRepository.setHideLogo(widget.system.id!, value);
    if (mounted) {
      await context.read<SqliteConfigProvider>().refreshSystem(_system);
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        (value ? AppLocale.systemLogoHidden : AppLocale.systemLogoShown)
            .getString(context),
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

      // Open file picker
      final result = await FilePicker.pickFiles(
        dialogTitle: AppLocale.selectEmulatorExecutable
            .getString(context)
            .replaceFirst('{name}', standalone.name),
        type: extension != null ? FileType.custom : FileType.any,
        allowedExtensions: extension != null ? [extension] : null,
        lockParentWindow: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final selectedPath = result.files.first.path;
      if (selectedPath == null) {
        return;
      }

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
        selectedPath,
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
      // Open file picker for RetroArch executable
      FilePickerResult? result = await FilePicker.pickFiles(
        type: Platform.isWindows ? FileType.custom : FileType.any,
        allowedExtensions: Platform.isWindows ? ['exe'] : null,
        dialogTitle: AppLocale.selectRetroArchExe.getString(context),
      );

      if (result == null || result.files.single.path == null) {
        return; // User cancelled
      }

      final selectedPath = result.files.single.path!;

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
        emulatorPath: selectedPath,
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

  Widget _buildGeneralTab() {
    return ListView(
      controller: _generalScrollController,
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 6.r),
      children: [_buildGeneralSettingsSection()],
    );
  }

  Widget _buildAppearanceTab() {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 6.r),
      children: [_buildSystemImagesSection()],
    );
  }

  Widget _buildSystemImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8.r),
          child: Text(
            AppLocale.systemImages.getString(context),
            style: TextStyle(
              fontSize: 12.r,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        _buildImagePickerItem(
          index: 0,
          key: _appearanceItemKeys[0],
          title: AppLocale.backgroundImage.getString(context),
          subtitle: AppLocale.backgroundImageSubtitle.getString(context),
          currentPath:
              _system.customBackgroundPath ?? _system.backgroundImage ?? '',
          hasCustom:
              _system.customBackgroundPath != null &&
              _system.customBackgroundPath!.isNotEmpty,
          onPick: _pickAndSaveImage,
          onReset: _resetImage,
        ),
        SizedBox(height: 6.r),
        _buildImagePickerItem(
          index: 1,
          key: _appearanceItemKeys[1],
          title: AppLocale.logoImage.getString(context),
          subtitle: AppLocale.logoImageSubtitle.getString(context),
          currentPath: _system.customLogoPath ?? '',
          hasCustom:
              _system.customLogoPath != null &&
              _system.customLogoPath!.isNotEmpty,
          onPick: _pickAndSaveLogoImage,
          onReset: _resetLogoImage,
        ),
      ],
    );
  }

  Widget _buildImagePickerItem({
    required int index,
    required Key key,
    required String title,
    required String subtitle,
    required String currentPath,
    required bool hasCustom,
    required VoidCallback onPick,
    required VoidCallback onReset,
  }) {
    final bool isFocused = _currentTab == 2 && _appearanceIndex == index;
    final theme = Theme.of(context);

    return Container(
      key: key,
      height: 50.r,
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      decoration: BoxDecoration(
        color: isFocused
            ? theme.colorScheme.secondary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8.r),
        border: isFocused
            ? Border.all(
                color: theme.colorScheme.secondary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: Row(
        children: [
          // Preview (Small)
          Container(
            key: ValueKey('${currentPath}_${_system.imageVersion}'),
            width: 36.r,
            height: 36.r,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: currentPath.isEmpty
                ? Icon(
                    Symbols.image_not_supported_rounded,
                    size: 16.r,
                    color: Colors.white54,
                  )
                : _buildPreviewImage(currentPath),
          ),

          SizedBox(width: 12.r),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.r,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  hasCustom
                      ? AppLocale.customImageSet.getString(context)
                      : subtitle,
                  style: TextStyle(
                    fontSize: 10.r,
                    color: hasCustom
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: hasCustom ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          // Buttons (Small & Compact)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onPick,
                icon: Icon(Symbols.upload_file_rounded, size: 16.r),
                tooltip: AppLocale.upload.getString(context),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 24.r, minHeight: 24.r),
                color: theme.colorScheme.primary,
              ),
              if (hasCustom) ...[
                SizedBox(width: 4.r),
                IconButton(
                  onPressed: onReset,
                  icon: Icon(Symbols.delete_outline_rounded, size: 16.r),
                  tooltip: AppLocale.reset.getString(context),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 24.r, minHeight: 24.r),
                  color: theme.colorScheme.error,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSaveImage() async {
    try {
      String? pickedPath;

      if (Platform.isAndroid && await PermissionService.isTelevision()) {
        if (!mounted) return;
        pickedPath = await TvDirectoryPicker.showFilePicker(
          context,
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        );
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          dialogTitle: 'Select Background Image',
          lockParentWindow: true,
        );
        pickedPath = result?.files.single.path;
      }

      if (pickedPath == null) return;

      final originalFile = File(pickedPath);
      if (!originalFile.existsSync()) return;

      final extension = path.extension(originalFile.path);
      const suffix = '_background';
      final fileName = '${_system.folderName}$suffix$extension';

      final userDataPath = await ConfigService.getUserDataPath();
      final targetDir = Directory(path.join(userDataPath, 'media', 'systems'));
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      final targetPath = path.join(targetDir.path, fileName);

      // Copy file
      await originalFile.copy(targetPath);

      // Evict from cache to ensure immediate UI update
      await FileImage(File(targetPath)).evict();

      // Nuclear option: Clear global image cache to force reload
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Update DB
      await SystemRepository.setCustomImages(
        _system.id!,
        backgroundPath: targetPath,
      );

      // Update State
      setState(() {
        // Increment version to force rebuild in dialog preview
        final newVersion = (_system.imageVersion) + 1;

        _system = _system.copyWith(
          customBackgroundPath: targetPath,
          imageVersion: newVersion,
        );
      });

      if (mounted) {
        // Refresh provider to update UI everywhere
        final configProvider = context.read<SqliteConfigProvider>();
        await configProvider.refreshSystem(_system);
        if (!mounted) return;

        AppNotification.showNotification(
          context,
          AppLocale.imageUpdatedSuccess.getString(context),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      _log.e('Error updating system background image: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorUpdatingImage
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _resetImage() async {
    try {
      await SystemRepository.setCustomImages(_system.id!, backgroundPath: '');

      // Clear global image cache to force reload
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      setState(() {
        _system = _system.copyWith(customBackgroundPath: '');
      });

      if (mounted) {
        // Refresh provider to update UI everywhere
        final configProvider = context.read<SqliteConfigProvider>();
        await configProvider.refreshSystem(_system);
        if (!mounted) return;

        AppNotification.showNotification(
          context,
          AppLocale.imageResetDefault.getString(context),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      _log.e('Error resetting system background image: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorResettingImage
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _pickAndSaveLogoImage() async {
    try {
      String? pickedPath;

      if (Platform.isAndroid && await PermissionService.isTelevision()) {
        if (!mounted) return;
        pickedPath = await TvDirectoryPicker.showFilePicker(
          context,
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        );
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          dialogTitle: 'Select Logo Image',
          lockParentWindow: true,
        );
        pickedPath = result?.files.single.path;
      }

      if (pickedPath == null) return;

      final originalFile = File(pickedPath);
      if (!originalFile.existsSync()) return;

      final extension = path.extension(originalFile.path);
      final fileName = '${_system.folderName}_logo$extension';

      final userDataPath = await ConfigService.getUserDataPath();
      final targetDir = Directory(path.join(userDataPath, 'media', 'systems'));
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      final targetPath = path.join(targetDir.path, fileName);

      await originalFile.copy(targetPath);

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      await SystemRepository.setCustomImages(_system.id!, logoPath: targetPath);

      setState(() {
        final newVersion = _system.imageVersion + 1;
        _system = _system.copyWith(
          customLogoPath: targetPath,
          imageVersion: newVersion,
        );
      });

      if (mounted) {
        final configProvider = context.read<SqliteConfigProvider>();
        await configProvider.refreshSystem(_system);
        if (!mounted) return;

        AppNotification.showNotification(
          context,
          AppLocale.imageUpdatedSuccess.getString(context),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      _log.e('Error updating system logo image: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorUpdatingImage
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _resetLogoImage() async {
    try {
      await SystemRepository.setCustomImages(_system.id!, logoPath: '');

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      setState(() {
        _system = _system.copyWith(customLogoPath: '');
      });

      if (mounted) {
        final configProvider = context.read<SqliteConfigProvider>();
        await configProvider.refreshSystem(_system);
        if (!mounted) return;

        AppNotification.showNotification(
          context,
          AppLocale.imageResetDefault.getString(context),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      _log.e('Error resetting system logo image: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.errorResettingImage
              .getString(context)
              .replaceFirst('{error}', e.toString()),
          type: NotificationType.error,
        );
      }
    }
  }

  Widget _buildPreviewImage(String path) {
    if (path.isEmpty) return const SizedBox.shrink();

    if (ImageUtils.isGif(path)) {
      return ShaderGifWidget(imagePath: path, key: ValueKey('preview_$path'));
    }

    if (File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Symbols.broken_image_rounded,
          size: 16.r,
          color: Colors.white24,
        ),
      );
    } else if (path.startsWith('assets')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Symbols.broken_image_rounded,
          size: 16.r,
          color: Colors.white24,
        ),
      );
    } else {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Symbols.broken_image_rounded,
          size: 16.r,
          color: Colors.white24,
        ),
      );
    }
  }

  Widget _buildGeneralSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSwitchItem(
          index: 0,
          key: _generalItemKeys[0],
          title: AppLocale.alwaysShowRomName.getString(context),
          subtitle: AppLocale.alwaysShowRomNameSubtitle.getString(context),
          value: _system.preferFileName,
          onChanged: _togglePreferFileName,
        ),
        SizedBox(height: 4.r),
        _buildSwitchItem(
          index: 1,
          key: _generalItemKeys[1],
          title: AppLocale.hideExtension.getString(context),
          subtitle: AppLocale.hideExtensionSubtitle.getString(context),
          value: _system.hideExtension,
          onChanged: _toggleHideExtension,
        ),
        SizedBox(height: 4.r),
        _buildSwitchItem(
          index: 2,
          key: _generalItemKeys[2],
          title: AppLocale.hideParentheses.getString(context),
          subtitle: AppLocale.hideParenthesesSubtitle.getString(context),
          value: _system.hideParentheses,
          onChanged: _toggleHideParentheses,
        ),
        SizedBox(height: 4.r),
        _buildSwitchItem(
          index: 3,
          key: _generalItemKeys[3],
          title: AppLocale.hideBrackets.getString(context),
          subtitle: AppLocale.hideBracketsSubtitle.getString(context),
          value: _system.hideBrackets,
          onChanged: _toggleHideBrackets,
        ),
        SizedBox(height: 4.r),
        _buildSwitchItem(
          index: 4,
          key: _generalItemKeys[4],
          title: AppLocale.hideSystemLogo.getString(context),
          subtitle: AppLocale.hideSystemLogoSubtitle.getString(context),
          value: _system.hideLogo,
          onChanged: _toggleHideLogo,
        ),

        if (widget.system.folderName != 'all' &&
            widget.system.folderName != 'android') ...[
          SizedBox(height: 4.r),
          _buildSwitchItem(
            index: 5,
            key: _generalItemKeys[5],
            title: AppLocale.recursiveScan.getString(context),
            subtitle: AppLocale.recursiveScanSubtitle.getString(context),
            value: _system.recursiveScan,
            onChanged: _toggleRecursiveScan,
          ),
        ],
      ],
    );
  }

  Widget _buildSwitchItem({
    required int index,
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final bool isFocused = _generalIndex == index;
    final theme = Theme.of(context);

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: isFocused
            ? theme.colorScheme.secondary.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: InkWell(
        onTap: () {
          SfxService().playNavSound();
          onChanged(!value);
        },
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 6.r),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10.r,
                        fontWeight: FontWeight.w600,
                        color: isFocused
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9.r,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              CustomToggleSwitch(
                value: value,
                onChanged: onChanged,
                activeColor: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmulatorsTab() {
    return _buildCoresList();
  }

  Widget _buildCoresList() {
    if (_totalEmulators == 0) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(8.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.gamepad_rounded,
                size: 28.r,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              SizedBox(height: 8.r),
              Text(
                AppLocale.noEmulatorsAvailable.getString(context),
                style: TextStyle(
                  fontSize: 12.r,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: _centeredScrollController.rebuildNotifier,
      builder: (context, rebuildCount, child) {
        return ListView.builder(
          key: ValueKey('emulators_list_rebuild_$rebuildCount'),
          controller: _centeredScrollController.scrollController,
          padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
          itemCount: _totalEmulators,
          itemBuilder: (context, index) {
            final item = _displayItems[index];
            final isSelected = _selectedIndex == index;

            if (item is EmulatorGroupedCoreItem) {
              return _buildGroupedCoreItem(item, index, isSelected);
            } else if (item is EmulatorCoreItem) {
              return _buildCoreItem(
                item.core,
                index,
                isSelected,
                item.retroArchConfigured,
                item.retroArchPath,
              );
            } else if (item is EmulatorStandaloneItem) {
              return _buildStandaloneItem(item, index, isSelected);
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

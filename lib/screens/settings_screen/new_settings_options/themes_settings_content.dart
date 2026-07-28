import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/widgets/theme_card.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/tv_directory_picker.dart';
import 'package:neostation/responsive.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'settings_title.dart';

/// A specialized content panel for selecting application color themes and visual themes.
///
/// Implements a responsive grid layout with hardware-mapped gamepad navigation
/// (Up/Down/Left/Right) and real-time theme application via ThemeProvider.
class ThemesSettingsContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;
  final ValueChanged<int>? onSelectionChanged;

  const ThemesSettingsContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
    this.onSelectionChanged,
  });

  @override
  State<ThemesSettingsContent> createState() => ThemesSettingsContentState();
}

class ThemesSettingsContentState extends State<ThemesSettingsContent> {
  final _log = LoggerService.instance;
  final ScrollController _scrollController = ScrollController();

  /// Keys used for calculating viewport alignment during grid-based navigation.
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _initializeKeys();
  }

  /// Populates the key list based on the total number of available themes.
  void _initializeKeys() {
    _itemKeys.clear();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // Total Items: Native System Theme + Registered Theme Variants + Import tile.
    final count = themeProvider.getThemeList().length + 2;
    for (int i = 0; i < count; i++) {
      _itemKeys.add(GlobalKey());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Resolves the total theme count.
  int getItemCount(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // System theme + registered variants + Import tile.
    return themeProvider.getThemeList().length + 2;
  }

  /// Dynamic Grid Resolution: Column count based on display geometry.
  int get _gridColumns => Responsive.getThemesCrossAxisCount(context);

  /// Vertical Progression: Moves focus to the element above in the grid.
  void navigateUp() {
    final newIndex = GridNavUtils.navigateUp(
      currentIndex: widget.selectedContentIndex,
      crossAxisCount: _gridColumns,
      maxItems: getItemCount(context),
    );
    widget.onSelectionChanged?.call(newIndex);
    _ensureSelectedItemVisible(newIndex);
  }

  /// Vertical Progression: Moves focus to the element below in the grid.
  void navigateDown() {
    final newIndex = GridNavUtils.navigateDown(
      currentIndex: widget.selectedContentIndex,
      crossAxisCount: _gridColumns,
      maxItems: getItemCount(context),
    );
    widget.onSelectionChanged?.call(newIndex);
    _ensureSelectedItemVisible(newIndex);
  }

  /// Horizontal Progression: Moves focus left or exits to the master menu if at boundary.
  bool navigateLeft() {
    final currentCol = widget.selectedContentIndex % _gridColumns;
    if (currentCol == 0) {
      return true; // Boundary reached: Return focus to the master menu.
    }

    final newIndex = GridNavUtils.navigateLeft(
      currentIndex: widget.selectedContentIndex,
      crossAxisCount: _gridColumns,
      maxItems: getItemCount(context),
    );
    widget.onSelectionChanged?.call(newIndex);
    _ensureSelectedItemVisible(newIndex);
    return false;
  }

  /// Horizontal Progression: Moves focus to the next element on the right.
  void navigateRight() {
    final newIndex = GridNavUtils.navigateRight(
      currentIndex: widget.selectedContentIndex,
      crossAxisCount: _gridColumns,
      maxItems: getItemCount(context),
    );
    widget.onSelectionChanged?.call(newIndex);
    _ensureSelectedItemVisible(newIndex);
  }

  /// Orchestrates visual alignment to ensure the focused theme card is within the viewport.
  void _ensureSelectedItemVisible(int index) {
    if (index >= 0 && index < _itemKeys.length) {
      final context = _itemKeys[index].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    }
  }

  /// Persistence Protocol: Updates the active application theme.
  void selectItem(int index) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final themes = themeProvider.getThemeList();

    if (index == 0) {
      // Index 0: Native System/Dynamic theme resolution.
      await themeProvider.setTheme('system');
    } else if (index - 1 < themes.length) {
      // Indices >0: Specific registered theme variants.
      await themeProvider.setTheme(themes[index - 1]['name']!);
    } else {
      // Last item: the "Import theme" tile.
      await _importTheme();
      return;
    }
    if (mounted) setState(() {});
    widget.onSelectionChanged?.call(index);
  }

  /// Opens a file picker, imports the selected daisyUI theme JSON, and applies
  /// it. Surfaces success/failure via [AppNotification].
  Future<void> _importTheme() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final pickerTitle = AppLocale.importTheme.getString(context);
    try {
      String? filePath;

      if (Platform.isAndroid && await PermissionService.isTelevision()) {
        // Android TV has no system file picker; use the in-app one.
        if (mounted) {
          filePath = await TvDirectoryPicker.showFilePicker(
            context,
            extensions: ['json'],
          );
        }
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          dialogTitle: pickerTitle,
        );
        filePath = result?.files.single.path;
      }

      if (filePath == null) return;

      final result = await themeProvider.importTheme(File(filePath));
      if (mounted) setState(() {});
      if (mounted) {
        final name = result.theme.name;
        AppNotification.showNotification(
          context,
          (result.created
                  ? AppLocale.importThemeSuccess
                  : AppLocale.importThemeExists)
              .getString(context)
              .replaceAll('%s', name),
          type: result.created
              ? NotificationType.success
              : NotificationType.info,
        );
      }
    } on FormatException catch (e) {
      _log.e('Theme import failed (malformed): $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.importThemeError.getString(context),
          type: NotificationType.error,
        );
      }
    } catch (e) {
      _log.e('Theme import failed: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.importThemeError.getString(context),
          type: NotificationType.error,
        );
      }
    }
  }

  /// Gamepad entry point: deletes the theme at [index] if it is a custom
  /// (imported) one. No-op for built-ins, 'system', or the Import tile.
  void deleteFocusedTheme(int index) {
    if (index <= 0) return;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final themes = themeProvider.getThemeList();
    final themeIndex = index - 1;
    if (themeIndex >= themes.length) return; // Import tile.
    final t = themes[themeIndex];
    if (!themeProvider.isCustomTheme(t['name']!)) return;
    _deleteTheme(t['name']!, t['displayName']!);
  }

  /// Confirms and deletes a user-imported theme.
  Future<void> _deleteTheme(String themeName, String displayName) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.deleteThemeTitle.getString(context),
      body: AppLocale.deleteThemeConfirm
          .getString(context)
          .replaceAll('%s', displayName),
      confirmLabel: AppLocale.delete.getString(context),
      icon: Symbols.delete_rounded,
    );
    if (!confirmed) return;

    await themeProvider.deleteTheme(themeName);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Contextual Theme Model construction.
    final List<Map<String, String>> allThemes = [
      {
        'name': 'system',
        'displayName': AppLocale.systemTheme.getString(context),
      },
      ...themeProvider.getThemeList(),
    ];

    // Synchronization of GlobalKeys with the dynamic theme list (+1 = Import tile).
    if (_itemKeys.length != allThemes.length + 1) {
      _initializeKeys();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.only(bottom: 24.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsTitle(
            title: AppLocale.themes.getString(context),
            subtitle: AppLocale.themesSubtitle.getString(context),
          ),
          SizedBox(height: 12.r),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: allThemes.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              crossAxisSpacing: 8.r,
              mainAxisSpacing: 8.r,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              // Focus Resolution: Determines if the item is currently highlighted via gamepad.
              final isFocused =
                  widget.isContentFocused &&
                  widget.selectedContentIndex == index;

              // Last item: the "Import theme" tile.
              if (index == allThemes.length) {
                return Container(
                  key: _itemKeys[index],
                  child: ImportThemeCard(
                    label: AppLocale.importTheme.getString(context),
                    isFocused: isFocused,
                    onTap: () {
                      SfxService().playNavSound();
                      widget.onSelectionChanged?.call(index);
                      selectItem(index);
                    },
                  ),
                );
              }

              final t = allThemes[index];

              // State Resolution: Determines if the theme is currently active.
              final isSelected =
                  themeProvider.currentThemeName == t['name'] ||
                  (index == 0 && themeProvider.currentThemeName == 'system');

              final isCustom = themeProvider.isCustomTheme(t['name']!);

              return Container(
                key: _itemKeys[index],
                child: ThemeCard(
                  themeName: t['name']!,
                  displayName: t['displayName']!,
                  isSelected: isSelected,
                  isFocused: isFocused,
                  onTap: () {
                    SfxService().playNavSound();
                    widget.onSelectionChanged?.call(index);
                    selectItem(index);
                  },
                  onLongPress: isCustom
                      ? () => _deleteTheme(t['name']!, t['displayName']!)
                      : null,
                  onDelete: isCustom
                      ? () => _deleteTheme(t['name']!, t['displayName']!)
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

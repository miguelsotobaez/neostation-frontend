import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/adaptive_scroll.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/palette_provider.dart';
import 'package:neostation/widgets/theme_card.dart';
import 'package:neostation/responsive.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'settings_title.dart';

/// A specialized content panel for selecting application color palettes and visual themes.
///
/// Implements a responsive grid layout with hardware-mapped gamepad navigation
/// (Up/Down/Left/Right) and real-time palette application via PaletteProvider.
class PaletteSettingsContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;
  final ValueChanged<int>? onSelectionChanged;

  const PaletteSettingsContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
    this.onSelectionChanged,
  });

  @override
  State<PaletteSettingsContent> createState() => PaletteSettingsContentState();
}

class PaletteSettingsContentState extends State<PaletteSettingsContent> {
  final ScrollController _scrollController = ScrollController();

  /// Keys used for calculating viewport alignment during grid-based navigation.
  final List<GlobalKey> _itemKeys = [];

  /// Snaps during rapid D-pad navigation, animates on a single move.
  final AdaptiveScroller _scroller = AdaptiveScroller();

  @override
  void initState() {
    super.initState();
    _initializeKeys();
  }

  /// Populates the key list based on the total number of available palettes.
  void _initializeKeys() {
    _itemKeys.clear();
    final paletteProvider = Provider.of<PaletteProvider>(
      context,
      listen: false,
    );
    // Total Items: Native System Theme + Registered Palette Variants.
    final count = paletteProvider.getPaletteList().length + 1;
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
    final paletteProvider = Provider.of<PaletteProvider>(
      context,
      listen: false,
    );
    return paletteProvider.getPaletteList().length + 1;
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
        _scroller.ensureVisible(context);
      }
    }
  }

  /// Persistence Protocol: Updates the active application theme.
  void selectItem(int index) async {
    final paletteProvider = Provider.of<PaletteProvider>(
      context,
      listen: false,
    );

    if (index == 0) {
      // Index 0: Native System/Dynamic palette resolution.
      await paletteProvider.setPalette('system');
    } else {
      // Indices >0: Specific registered palette variants.
      final palettes = paletteProvider.getPaletteList();
      final paletteIndex = index - 1;
      if (paletteIndex >= 0 && paletteIndex < palettes.length) {
        await paletteProvider.setPalette(palettes[paletteIndex]['name']!);
      }
    }
    if (mounted) setState(() {});
    widget.onSelectionChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final paletteProvider = Provider.of<PaletteProvider>(context);

    // Contextual Palette Model construction.
    final List<Map<String, String>> allThemes = [
      {
        'name': 'system',
        'displayName': AppLocale.systemTheme.getString(context),
        'logoPath': paletteProvider.getCurrentLogoPath(),
      },
      ...paletteProvider.getPaletteList(),
    ];

    // Synchronization of GlobalKeys with the dynamic theme list.
    if (_itemKeys.length != allThemes.length) {
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
            title: AppLocale.palettes.getString(context),
            subtitle: AppLocale.palettesSubtitle.getString(context),
          ),
          SizedBox(height: 12.r),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: allThemes.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              crossAxisSpacing: 8.r,
              mainAxisSpacing: 8.r,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final t = allThemes[index];

              // State Resolution: Determines if the palette is currently active.
              final isSelected =
                  paletteProvider.currentPaletteName == t['name'] ||
                  (index == 0 &&
                      paletteProvider.currentPaletteName == 'system');

              // Focus Resolution: Determines if the item is currently highlighted via gamepad.
              final isFocused =
                  widget.isContentFocused &&
                  widget.selectedContentIndex == index;

              return Container(
                key: _itemKeys[index],
                child: ThemeCard(
                  themeName: t['name']!,
                  displayName: t['displayName']!,
                  logoPath: t['logoPath']!,
                  isSelected: isSelected,
                  isFocused: isFocused,
                  onTap: () {
                    SfxService().playNavSound();
                    widget.onSelectionChanged?.call(index);
                    selectItem(index);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// An autonomous gamepad-navigable overlay for language selection.
class LanguagePickerOverlay extends StatefulWidget {
  final Offset anchorOffset;
  final String currentLang;

  const LanguagePickerOverlay({
    super.key,
    required this.anchorOffset,
    required this.currentLang,
  });

  @override
  State<LanguagePickerOverlay> createState() => LanguagePickerOverlayState();
}

class LanguagePickerOverlayState extends State<LanguagePickerOverlay> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;

  static final _languages = AppLocale.supportedLanguages.entries
      .map((e) => (e.key, e.value))
      .toList();

  final List<GlobalKey> _itemKeys = List.generate(
    _languages.length,
    (_) => GlobalKey(),
  );
  final GlobalKey _colKey = GlobalKey();
  double _indicatorTop = -1;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _languages.indexWhere((l) => l.$1 == widget.currentLang);
    if (_selectedIndex < 0) _selectedIndex = 0;

    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        setState(() {
          _selectedIndex =
              (_selectedIndex - 1 + _languages.length) % _languages.length;
        });
        _updateIndicator();
        SfxService().playNavSound();
      },
      onNavigateDown: () {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _languages.length;
        });
        _updateIndicator();
        SfxService().playNavSound();
      },
      onSelectItem: _handleSelection,
      onBack: () => Navigator.pop(context),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'language_picker_overlay',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
      _updateIndicator();
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('language_picker_overlay');
    _gamepadNav.dispose();
    super.dispose();
  }

  /// Calculates the visual position of the selection indicator.
  void _updateIndicator() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _itemKeys[_selectedIndex];
      final RenderBox? box =
          key.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? colBox =
          _colKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && colBox != null) {
        final pos = box.localToGlobal(Offset.zero, ancestor: colBox);
        setState(() => _indicatorTop = pos.dy);
      }
    });
  }

  void _handleSelection() {
    SfxService().playEnterSound();
    Navigator.pop(context, _languages[_selectedIndex].$1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final overlayWidth = 180.r;
    final itemHeight = 24;
    final overlayHeight = itemHeight * _languages.length + 16;

    // Anchor: Right-aligned relative to the trigger button, clamped to viewport boundaries.
    double left = widget.anchorOffset.dx - overlayWidth;
    double top = widget.anchorOffset.dy - overlayHeight.r / 1.5;
    left = left.clamp(8.0, screenSize.width - overlayWidth - 8);
    top = top.clamp(8.0, screenSize.height - overlayHeight - 8);

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: overlayWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                key: _colKey,
                children: [
                  if (_indicatorTop >= 0)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      top: _indicatorTop,
                      left: 6.r,
                      right: 4.r,
                      height: itemHeight.r,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            width: 0.5.r,
                          ),
                        ),
                      ),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _languages.asMap().entries.map((entry) {
                      final i = entry.key;
                      final lang = entry.value;
                      final isSelected = lang.$1 == widget.currentLang;
                      return SizedBox(
                        key: _itemKeys[i],
                        height: itemHeight.r,
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = i);
                            _handleSelection();
                          },
                          onHover: (v) {
                            if (v) {
                              setState(() => _selectedIndex = i);
                              _updateIndicator();
                            }
                          },
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.r),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    lang.$2,
                                    style: TextStyle(
                                      fontSize: 10.r,
                                      color: isSelected
                                          ? theme.colorScheme.secondary
                                          : theme.colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Symbols.check_rounded,
                                    size: 12.r,
                                    color: theme.colorScheme.secondary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

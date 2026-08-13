import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/app_locale.dart';
import '../../services/game_service.dart' show GamepadNavigationManager;
import '../../utils/gamepad_nav.dart';
import '../../widgets/neo_glass.dart';
import '../../themes/chrome_surface.dart';

/// Full-screen, offline PDF reader for a locally cached game manual.
///
/// The PDF itself is rendered by pdfrx. NeoStation only owns the surrounding
/// chrome and a small modal gamepad layer so B always returns to Game Settings.
class GameManualReaderScreen extends StatefulWidget {
  final String manualPath;
  final String gameTitle;

  const GameManualReaderScreen({
    super.key,
    required this.manualPath,
    required this.gameTitle,
  });

  @override
  State<GameManualReaderScreen> createState() => _GameManualReaderScreenState();
}

class _GameManualReaderScreenState extends State<GameManualReaderScreen> {
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onBack: _close,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'game_manual_reader',
        modal: true,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('game_manual_reader');
    _gamepadNav.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PdfViewer.file(widget.manualPath),
            ),
            Positioned(
              left: 12.r,
              right: 12.r,
              top: 8.r,
              child: NeoGlass(
                role: GlassSurfaceRole.chrome,
                borderRadius: BorderRadius.circular(12.r),
                padding: EdgeInsets.symmetric(horizontal: 10.r, vertical: 7.r),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _close,
                        borderRadius: BorderRadius.circular(8.r),
                        child: Padding(
                          padding: EdgeInsets.all(4.r),
                          child: Icon(
                            Symbols.arrow_back_rounded,
                            size: 18.r,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.r),
                    Icon(
                      Symbols.menu_book_rounded,
                      size: 18.r,
                      color: theme.colorScheme.primary,
                    ),
                    SizedBox(width: 7.r),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocale.manual.getString(context),
                            style: TextStyle(
                              fontSize: 11.r,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            widget.gameTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 8.5.r,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.62,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      AppLocale.pinchToZoom.getString(context),
                      style: TextStyle(
                        fontSize: 8.r,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

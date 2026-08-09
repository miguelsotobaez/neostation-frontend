import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/retro_achievements_helper.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/themes/corner_radii.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import '../tabs/game_details_achievements_tab.dart';

/// A full-screen dialog that displays RetroAchievements progress for a single game.
///
/// Loads its own metadata, supports pull-to-refresh style updates via the embedded
/// achievements tab, and closes on touch back-button or gamepad B.
class GameAchievementsDialog extends StatefulWidget {
  final GameModel game;
  final SystemModel system;
  final RetroAchievementsProvider retroAchievementsProvider;

  const GameAchievementsDialog({
    super.key,
    required this.game,
    required this.system,
    required this.retroAchievementsProvider,
  });

  @override
  State<GameAchievementsDialog> createState() => _GameAchievementsDialogState();
}

class _GameAchievementsDialogState extends State<GameAchievementsDialog> {
  GameInfoAndUserProgress? _gameInfo;
  bool _isLoading = false;
  GamepadNavigation? _gamepadNav;

  @override
  void initState() {
    super.initState();
    _initializeGamepad();
    _loadAchievements();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('game_achievements_dialog');
    _gamepadNav?.dispose();
    super.dispose();
  }

  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onBack: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
    _gamepadNav?.initialize();
    GamepadNavigationManager.pushLayer(
      'game_achievements_dialog',
      onActivate: () => _gamepadNav?.activate(),
      onDeactivate: () => _gamepadNav?.deactivate(),
    );
  }

  Future<void> _loadAchievements({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final info = await RetroAchievementsHelper.loadGameInfo(
        game: widget.game,
        provider: widget.retroAchievementsProvider,
        effectiveSystem: widget.system,
        isAllMode: false,
        forceRefresh: forceRefresh,
      );

      if (forceRefresh && info != null) {
        RetroAchievementsHelper.evictBadgeCache(_gameInfo);
      }

      if (mounted) {
        setState(() {
          _gameInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gameInfo = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 24.r),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: size.width * 0.7,
          maxHeight: size.height * 0.7,
        ),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: radii.radiusExternal,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
            width: 1.r,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12.r,
              offset: Offset(0, 4.r),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radii.radiusExternal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Achievements content: the tab widget is designed for a Stack
              // with fixed offsets, so we place it directly in this Stack.
              GameDetailsAchievementsTab(
                gameInfo: _gameInfo,
                isLoading: _isLoading,
                topOffset: 0,
                bottomOffset: 0,
                leftOffset: 0,
                rightOffset: 0,
                headerAction: HeaderActionButton(
                  icon: Image.asset(
                    'assets/images/gamepad/Xbox_B_button.png',
                    width: 12.r,
                    height: 12.r,
                    color: theme.colorScheme.onPrimary,
                  ),
                  label: AppLocale.back.getString(context).toUpperCase(),
                  onTap: () => Navigator.of(context).pop(),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onRefresh: () {
                  SfxService().playNavSound();
                  _loadAchievements(forceRefresh: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

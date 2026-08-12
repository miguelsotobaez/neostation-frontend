import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../services/sfx_service.dart';
import '../themes/corner_radii.dart';

/// Sound effect played when a [GameActionButton] is tapped.
enum GameActionButtonSound {
  /// Confirm / primary action (A button, play, scrape).
  enter,

  /// Back / cancel action (B button).
  back,

  /// Generic navigation action (X, Y, Menu, View, random).
  nav,
}

/// A tall vertical action button used in the game list / grid / carousel.
///
/// Shows a Material Symbols icon in the upper badge area and a small gamepad
/// hint icon at the bottom, matching the vertical action column style.
class GameActionButton extends StatelessWidget {
  final Key? buttonKey;
  final String iconPath;
  final IconData symbol;
  final Color color;
  final Color? foregroundColor;
  final VoidCallback? onTap;
  final bool isLoading;

  /// Optional SFX to play when the button is tapped. Disabled buttons and
  /// buttons with no callback never play a sound.
  final GameActionButtonSound? sound;

  const GameActionButton({
    super.key,
    this.buttonKey,
    required this.iconPath,
    required this.symbol,
    required this.color,
    this.foregroundColor,
    this.onTap,
    this.isLoading = false,
    this.sound,
  });

  @override
  Widget build(BuildContext context) {
    // Enlarged a little for better legibility/touch visibility on the left
    // action rail, while keeping the same overall visual style.
    const double buttonWidth = 34.0;
    const double buttonHeight = 44.0;
    const double badgeHeight = 22.0;
    const double mainIconSize = 15.0;
    final cornerRadius =
        Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
        BorderRadius.circular(14.r);
    final badgeRadius = BorderRadius.only(
      topLeft: cornerRadius.topLeft,
      topRight: cornerRadius.topRight,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        key: buttonKey,
        onTap: isLoading || onTap == null ? null : _onTap,
        borderRadius: cornerRadius,
        child: Container(
          margin: EdgeInsets.only(bottom: 3.r),
          width: buttonWidth.r,
          height: buttonHeight.r,
          decoration: BoxDecoration(
            color: color,
            borderRadius: cornerRadius,
            border: Border.all(
              color: color,
              width: 2.r,
              strokeAlign: BorderSide.strokeAlignCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.3),
                blurRadius: 3.r,
                offset: Offset(1.5.r, 1.5.r),
              ),
            ],
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 16.r,
                    height: 16.r,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.r,
                      color: foregroundColor,
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Action icon badge anchored to the top of the button,
                    // spanning the full width with a low height so it shows
                    // less than half of the button.
                    Container(
                      height: badgeHeight.r,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: badgeRadius,
                      ),
                      child: Center(
                        child: Icon(
                          symbol,
                          size: mainIconSize.r,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                    // Gamepad hint icon centered in the lower area.
                    Expanded(
                      child: Center(
                        child: Image.asset(
                          iconPath,
                          width: 17.r,
                          height: 17.r,
                          color: foregroundColor,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _onTap() {
    switch (sound) {
      case GameActionButtonSound.enter:
        SfxService().playEnterSound();
      case GameActionButtonSound.back:
        SfxService().playBackSound();
      case GameActionButtonSound.nav:
        SfxService().playNavSound();
      case null:
        break;
    }
    onTap?.call();
  }
}

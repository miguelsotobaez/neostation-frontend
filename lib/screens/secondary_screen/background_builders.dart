import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/secondary_display_state.dart';
import '../../widgets/shaders/shader_gif_widget.dart';
import '../../utils/image_utils.dart' as image_utils;

/// Pure background/artwork builders for the secondary display.
///
/// Extracted verbatim from `_SecondaryScreenState` — every function is a pure
/// mapping from a [SecondaryDisplayStateData] snapshot (plus constant styling)
/// to a widget subtree, with no reference to widget state. Behaviour and the
/// rendered tree are unchanged.

Widget buildBackgroundBytes(Uint8List bytes, {BoxFit fit = BoxFit.contain}) {
  return Image.memory(
    bytes,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => buildDefaultBackground(),
  );
}

Widget buildBackground(String path, {BoxFit fit = BoxFit.contain}) {
  final file = File(path);
  if (file.existsSync()) {
    if (image_utils.ImageUtils.isGif(path)) {
      return ShaderGifWidget(
        imagePath: path,
        key: ValueKey('secondary_bg_$path'),
        fit: fit,
      );
    }
    return Image.file(file, fit: fit);
  }
  return buildDefaultBackground();
}

Widget buildDefaultBackground() {
  return const SizedBox.shrink();
}

/// Mirrors the main screen's game art as a fallback when no screenshot or
/// video is available: fanart filling the screen (cover) with the game's
/// wheel/logo centered on top. Either asset is optional — a logo-only game
/// shows just the centered logo over the app background, and a fanart-only
/// game shows just the fanart.
Widget buildFanartWithLogo(SecondaryDisplayStateData value) {
  return Stack(
    fit: StackFit.expand,
    children: [
      if (value.gameFanart != null)
        buildBackground(value.gameFanart!, fit: BoxFit.cover),
      // Optional scrim over the fanart only (below the logo) so a busy
      // background doesn't clash with the logo. The logo, drawn next, stays
      // at full brightness.
      if (value.gameFanart != null && value.fanartDimLevel > 0)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(
              alpha: value.fanartDimLevel.clamp(0, 100) / 100.0,
            ),
          ),
        ),
      if (value.gameWheel != null)
        Center(
          child: Padding(
            padding: EdgeInsets.all(48.r),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Drop shadow: black-tinted copy offset behind the logo,
                // mirroring the main screen's wheel shadow treatment.
                Transform.translate(
                  offset: Offset(4.r, 4.r),
                  child: Image.file(
                    File(value.gameWheel!),
                    fit: BoxFit.contain,
                    width: 600.r,
                    filterQuality: FilterQuality.low,
                    cacheWidth: 32,
                    color: Colors.black.withValues(alpha: 0.7),
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
                Image.file(
                  File(value.gameWheel!),
                  fit: BoxFit.contain,
                  width: 600.r,
                  cacheWidth: 640,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

Widget buildUnifiedAppBackground(SecondaryDisplayStateData value) {
  if (value.isOled) {
    return Container(
      color: value.backgroundColor != null
          ? Color(value.backgroundColor!)
          : Colors.black,
    );
  }

  return Builder(
    builder: (context) {
      final bg = Theme.of(context).scaffoldBackgroundColor;
      return Container(decoration: BoxDecoration(color: bg));
    },
  );
}

Widget buildSystemBackground(SecondaryDisplayStateData value) {
  // Note: OLED is intentionally NOT short-circuited here. For a highlighted
  // system the console artwork IS the background, so blacking it out would
  // leave only the console name on screen. The black/background-color
  // fallback below (via buildShaderFallback) still applies when no system
  // image is available, preserving the OLED look in the empty case.
  final bgPath = value.systemBackground;
  final hasBg = bgPath != null && bgPath.isNotEmpty;

  if (hasBg) {
    final isGif = image_utils.ImageUtils.isGif(bgPath);

    Widget? art;
    if (value.isBackgroundAsset) {
      if (isGif) {
        art = ShaderGifWidget(
          imagePath: bgPath,
          key: ValueKey('secondary_system_bg_$bgPath'),
        );
      } else {
        art = Image.asset(
          bgPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              buildShaderFallback(value),
        );
      }
    } else {
      final file = File(bgPath);
      if (file.existsSync()) {
        if (isGif) {
          art = ShaderGifWidget(
            imagePath: bgPath,
            key: ValueKey('secondary_system_bg_$bgPath'),
          );
        } else {
          art = Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                buildShaderFallback(value),
          );
        }
      }
    }

    if (art != null) {
      return _withFanartDim(art, value);
    }
  }

  return buildShaderFallback(value);
}

/// Overlays the same dim scrim used behind game logos so system console
/// artwork doesn't clash with the system name/logo drawn on top. Mirrors the
/// scrim in [buildFanartWithLogo]; a no-op when the dim level is 0.
Widget _withFanartDim(Widget art, SecondaryDisplayStateData value) {
  if (value.fanartDimLevel <= 0) return art;
  return Stack(
    fit: StackFit.expand,
    children: [
      art,
      Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(
            alpha: value.fanartDimLevel.clamp(0, 100) / 100.0,
          ),
        ),
      ),
    ],
  );
}

Widget buildShaderFallback(SecondaryDisplayStateData value) {
  return Container(
    color: value.backgroundColor != null
        ? Color(value.backgroundColor!)
        : Colors.black,
  );
}

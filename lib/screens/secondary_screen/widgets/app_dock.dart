import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/secondary_apps_service.dart';
import '../../../models/config_model.dart';
import '../../../models/secondary_display_state.dart';
import '../now_playing_helpers.dart';

/// The bottom app dock on the Now Playing screen: a centered row of launch
/// slots. Filled slots launch their app (long-press clears); empty slots open
/// the app picker for that index.
///
/// Pure, input-driven subtree — the owning [SecondaryScreen] passes the current
/// state snapshot plus the three slot callbacks, so the dock re-reads no
/// provider state of its own.
class AppDock extends StatelessWidget {
  const AppDock({
    super.key,
    required this.value,
    required this.onLaunchApp,
    required this.onPickSlot,
    required this.onClearSlot,
  });

  final SecondaryDisplayStateData value;

  /// Launches the docked app in [package] (prefers the bottom display).
  final void Function(String package) onLaunchApp;

  /// Opens the app picker to assign an app to the empty slot [index].
  final void Function(int index) onPickSlot;

  /// Clears the app assigned to slot [index].
  final void Function(int index) onClearSlot;

  @override
  Widget build(BuildContext context) {
    if (!value.dockEnabled) return const SizedBox.shrink();
    final apps = ConfigModel.normalizeDock(value.dockApps);
    final scheme = panelScheme(value);
    final visibleSlots = value.dockSlotCount.clamp(
      ConfigModel.dockMinSlotCount,
      ConfigModel.dockMaxSlotCount,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            scheme.shadow.withValues(alpha: 0.55),
            scheme.shadow.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < visibleSlots; i++) ...[
            if (i > 0) SizedBox(width: 14.r),
            _buildDockSlot(i, apps[i], scheme),
          ],
        ],
      ),
    );
  }

  /// A single dock slot. [package] empty = free slot.
  Widget _buildDockSlot(int index, String package, ColorScheme scheme) {
    final filled = package.isNotEmpty;
    return GestureDetector(
      onTap: () => filled ? onLaunchApp(package) : onPickSlot(index),
      onLongPress: filled ? () => onClearSlot(index) : null,
      child: Container(
        width: 56.r,
        height: 56.r,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: filled ? 0.10 : 0.05),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: filled ? 0.22 : 0.14),
          ),
        ),
        child: filled
            ? Padding(
                padding: EdgeInsets.all(8.r),
                child: buildDockIcon(package),
              )
            : Icon(
                Symbols.add_rounded,
                color: scheme.onSurface.withValues(alpha: 0.45),
                size: 26.r,
              ),
      ),
    );
  }
}

/// Lazily loads and renders a docked app's launcher icon (cached in
/// [SecondaryAppsService]). Shared by the dock slots and the app-picker tiles.
Widget buildDockIcon(String package) {
  return FutureBuilder<Uint8List?>(
    future: SecondaryAppsService.getAppIcon(package),
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
      }
      return Icon(
        Symbols.android_rounded,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        size: 24.r,
      );
    },
  );
}

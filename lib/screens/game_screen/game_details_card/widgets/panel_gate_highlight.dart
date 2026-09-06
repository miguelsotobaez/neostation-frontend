import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The panel-level affordance that replaced the header's A / B gate chip.
///
/// The chip only *told* the user the panel could be driven, and it cost every
/// panel that has a gate a slot in its header. Lighting up the panel's own edge
/// says the same thing where the user is already looking, and it leaves the
/// whole panel free to double as the touch target.
///
/// Three states, quietest first:
/// - nothing in there to drive: the panel's resting edge.
/// - drivable: a dimmed accent edge, "there is something in here".
/// - active: the full accent edge, in the colour every focused element in the
///   card already uses, plus a soft glow so the panel reads as the thing
///   holding the D-pad.
///
/// The edge keeps the same width in all three states and only changes colour.
/// A border is part of a box's inset, so a thicker "active" edge would move
/// every line of the panel's content inward at the moment it was entered.
class PanelGateHighlight {
  const PanelGateHighlight._();

  /// Width of the panel edge, in every state.
  static double width(BuildContext context) => 2.r;

  /// How long the edge takes to change state. Short enough to read as a
  /// response to the button rather than as an animation of its own.
  static const Duration duration = Duration(milliseconds: 160);

  /// The panel's edge for the given gate state.
  ///
  /// [restingColor] is what the panel draws with no gate to advertise; pass
  /// [Colors.transparent] for a panel that draws no visible edge of its own.
  static Border border(
    BuildContext context, {
    required bool isDrivable,
    required bool isActive,
    required Color restingColor,
  }) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Border.all(
      color: isActive
          ? accent
          : (isDrivable ? accent.withValues(alpha: 0.5) : restingColor),
      width: width(context),
    );
  }

  /// The panel's shadows, with the active panel's glow folded in.
  static List<BoxShadow> shadows(
    BuildContext context, {
    required bool isActive,
    required BoxShadow resting,
  }) {
    if (!isActive) return [resting];
    return [
      resting,
      BoxShadow(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.35),
        blurRadius: 8.r,
      ),
    ];
  }
}

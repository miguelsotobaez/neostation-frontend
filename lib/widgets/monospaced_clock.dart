import 'package:flutter/material.dart';

/// A clock reading whose glyphs do not move as the number changes.
///
/// The app's typeface (Anta) carries no `tnum` table, so
/// [FontFeature.tabularFigures] — which the footers used to rely on — is
/// silently a no-op and every digit is its own width. Measured on device,
/// "00:00:40" ran 19 logical pixels wider than "00:01:20": right-aligned at the
/// end of the details footer, that walked the whole reading sideways whenever a
/// digit changed, and a ticking clock did it once a second.
///
/// So the cells are made by hand: every digit gets the width of the widest
/// digit in this style and is centred in it, which is what tabular figures
/// would have done. The separators keep their own width — they never vary.
///
/// Shared by the details footer and the grid/carousel footer so the two cannot
/// drift; it lived as a private class in the former until the latter's play
/// time stopped being a pill and needed the same treatment (D15).
class MonospacedClock extends StatelessWidget {
  final String text;
  final TextStyle style;

  const MonospacedClock({super.key, required this.text, required this.style});

  /// Formats accumulated seconds as a zero-padded HH:MM:SS reading.
  static String format(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(h)}:${pad(m)}:${pad(s)}';
  }

  /// Cache of the per-style measurements, keyed by the two things that change
  /// them. Without this, every selection change would re-lay-out eleven
  /// throwaway [TextPainter]s.
  static final Map<String, _ClockMetrics> _metricsCache = {};

  static _ClockMetrics _metricsFor(TextStyle style, TextScaler scaler) {
    final String key =
        '${style.fontSize}/${style.fontWeight}/'
        '${scaler.scale(100)}/${style.fontFamily}';
    return _metricsCache.putIfAbsent(key, () {
      double widthOf(String character) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: character, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final double width = painter.width;
        painter.dispose();
        return width;
      }

      double widest = 0;
      for (int digit = 0; digit <= 9; digit++) {
        final double width = widthOf('$digit');
        if (width > widest) widest = width;
      }
      return _ClockMetrics(digit: widest, separator: widthOf(':'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final _ClockMetrics metrics = _metricsFor(
      style,
      MediaQuery.textScalerOf(context),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final String character in text.split(''))
          SizedBox(
            width: character == ':' ? metrics.separator : metrics.digit,
            child: Text(character, textAlign: TextAlign.center, style: style),
          ),
      ],
    );
  }
}

/// The cell widths a clock reading is laid out on.
class _ClockMetrics {
  final double digit;
  final double separator;

  const _ClockMetrics({required this.digit, required this.separator});
}

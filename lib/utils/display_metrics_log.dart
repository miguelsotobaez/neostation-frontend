import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/services/logger_service.dart';

/// The last signature logged per display, so a rotation, a density override or
/// a resized desktop window re-logs, while an ordinary rebuild does not.
final Map<String, String> _lastSignature = {};

/// Logs the display metrics ScreenUtil resolved for [display] (`main` or
/// `secondary`).
///
/// Every `.r`, `.sp` and `.w` in the UI is derived from these numbers, so a
/// layout report from a device we do not own is close to unactionable without
/// them — asking a user to describe how big the text looks is not a
/// measurement. This puts the actual factors in the log they already send.
///
/// Call from inside a `ScreenUtilInit` builder: that runs after `configure()`,
/// and [ScreenUtil] reads the `MediaQueryData` belonging to *this* engine, so
/// the secondary display reports itself rather than the primary view.
///
/// Both scale factors are logged because they are not interchangeable. `.sp`
/// is `scaleWidth` — `ScreenUtilInit` installs a non-nullable
/// `fontSizeResolver` defaulting to `FontSizeResolvers.width`, which bypasses
/// `scaleText` and makes `minTextAdapt` unreachable. `.r` is
/// `min(scaleWidth, scaleHeight)` and is what the app sizes the overwhelming
/// majority of its fonts with. The two agree whenever `scaleWidth <=
/// scaleHeight` and diverge on wide-and-short panels such as the Steam Deck.
void logDisplayMetrics(BuildContext context, String display) {
  try {
    final u = ScreenUtil();
    final view = View.maybeOf(context);
    final dpr = view?.devicePixelRatio;
    final physical = view?.physicalSize;

    // Android's density bucket. Flutter's devicePixelRatio *is*
    // DisplayMetrics.density and density == densityDpi / 160, so this is the
    // exact figure `wm density` reports and `./sim-rgds.sh` takes as its
    // argument — a report that quotes it is a one-command repro.
    //
    // It is derived, not new information: at the 4dp the line prints, dpr does
    // multiply back cleanly. It is logged anyway so nobody reading a support
    // log has to do the arithmetic or decide how to round. (At the 2dp this
    // line used to print, 2.31 x 160 = 369.6 and the figure really was
    // unrecoverable — hence the precision bump alongside it.)
    //
    // Android-only: elsewhere dpr is not a density bucket, and the Deck's 1.0
    // would report a meaningless 160.
    final densityDpi = Platform.isAndroid && dpr != null
        ? (dpr * 160).round()
        : null;

    final sw = u.scaleWidth;
    final sh = u.scaleHeight;
    final r = u.radius(1);
    final sp = u.setSp(1);

    String f(double? v, [int p = 3]) => v == null ? '?' : v.toStringAsFixed(p);

    final signature =
        '${f(sw)}|${f(sh)}|${f(r)}|${f(sp)}|'
        '${f(u.screenWidth, 1)}x${f(u.screenHeight, 1)}|${u.orientation}';
    if (_lastSignature[display] == signature) return;
    final changed = _lastSignature.containsKey(display);
    _lastSignature[display] = signature;

    final log = LoggerService.instance;
    final tag = '[display:$display]${changed ? ' (changed)' : ''}';
    final lines = [
      '$tag physical='
          '${physical == null ? '?' : '${physical.width.toStringAsFixed(0)}x'
                    '${physical.height.toStringAsFixed(0)}'}'
          ' dpr=${f(dpr, 4)}'
          '${densityDpi == null ? '' : ' densityDpi=$densityDpi'}'
          ' logical=${f(u.screenWidth, 1)}x${f(u.screenHeight, 1)}'
          ' orientation=${u.orientation.name}',
      '$tag design=640x480'
          ' scaleWidth=${f(sw)} scaleHeight=${f(sh)}'
          ' .r=${f(r)} .sp=${f(sp)}'
          ' osTextScale=${f(u.textScaleFactor, 2)}',
    ];

    for (final line in lines) {
      log.i(line);
      // The secondary display's isolate has no file-backed logger, so a plain
      // log.i() there reaches only the console and never app.log — the file a
      // user actually sends with a bug report. Mirror to debugPrint so the
      // numbers survive in logcat / stdout at least.
      if (!log.isFileBacked) debugPrint(line);
    }
  } catch (e) {
    // Diagnostics must never take the app down on an unfamiliar device — the
    // one place this would run is exactly where something is already odd.
    LoggerService.instance.w('[display:$display] metrics unavailable: $e');
  }
}

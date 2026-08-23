import 'dart:async';

import 'package:flutter/material.dart';

/// Process-wide cache of measured cover-art aspect ratios, keyed by cover URL.
///
/// The RomM grid lays rows out from each card's height/width ratio the same way
/// the local game grid does — but where the local grid reads that ratio out of
/// the DB or an image header on disk, remote covers only reveal their size once
/// they decode. So the grid starts every unmeasured card at [fallback] and
/// upgrades it as the artwork arrives.
///
/// In practice RomM covers come from IGDB and virtually all share one aspect,
/// so the fallback is already correct for most of them and the settle is
/// invisible. Measurements are cached for the process lifetime, which means
/// scrolling back over a region never reflows it a second time.
class RommCoverAspect {
  RommCoverAspect._();

  /// Measured height/width ratios, keyed by cover URL.
  static final Map<String, double> _ratios = {};

  /// URLs with a measurement already in flight, so a card rebuilt mid-decode
  /// doesn't stack up duplicate stream listeners.
  static final Set<String> _pending = {};

  /// Ratio assumed until the real artwork has decoded. IGDB covers are 264x374
  /// (≈1.417 h/w), which is what the overwhelming majority of RomM libraries
  /// serve.
  static const double fallback = 1.417;

  /// The measured ratio for [url], or null if it hasn't decoded yet.
  static double? ratioOf(String? url) => url == null ? null : _ratios[url];

  /// True once [url] has a measurement (so callers can skip re-requesting it).
  static bool isMeasured(String? url) =>
      url != null && _ratios.containsKey(url);

  /// Resolves [url]'s intrinsic size and caches its ratio, invoking
  /// [onMeasured] once the real value differs from what was assumed.
  ///
  /// [image] must be the same [ImageProvider] the card renders with so the two
  /// share one entry in Flutter's image cache — [NetworkImage] equality is by
  /// URL, so measuring here never costs an extra fetch.
  ///
  /// [onMeasured] is always deferred to a microtask, never called inline.
  /// Callers request measurements from `build`, and an image already sitting in
  /// the cache completes its stream listener *synchronously* on `addListener` —
  /// so a direct call would land a `setState` in the middle of a build.
  static void measure(
    String url,
    ImageProvider image,
    VoidCallback onMeasured,
  ) {
    if (_ratios.containsKey(url) || _pending.contains(url)) return;
    _pending.add(url);

    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        _pending.remove(url);
        // Each listener receives its OWN clone of the ImageInfo and owns it, so
        // this must be disposed or every measured cover leaks a handle. Dispose
        // the ImageInfo rather than `info.image` directly — that also releases
        // the wrapper, and it only drops this clone's reference, never the
        // cached image the card is painting.
        final w = info.image.width;
        final h = info.image.height;
        info.dispose();
        if (w <= 0 || h <= 0) return;
        final ratio = h / w;
        _ratios[url] = ratio;
        // Only disturb the layout when the assumption was actually wrong.
        if ((ratio - fallback).abs() > 0.01) scheduleMicrotask(onMeasured);
      },
      onError: (_, _) {
        stream.removeListener(listener);
        _pending.remove(url);
        // Pin the fallback so a broken cover isn't retried on every rebuild.
        _ratios[url] = fallback;
      },
    );
    stream.addListener(listener);
  }
}

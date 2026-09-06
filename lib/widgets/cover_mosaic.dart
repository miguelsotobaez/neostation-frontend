import 'dart:io';

import 'package:flutter/material.dart';

/// Fills its box with 1–4 cover images.
///
/// The layout is the one the subfolder preview cards already use: a single
/// cover fills the whole box, two split it into columns, and three or four
/// stack into two rows (a three-cover set gives the bottom row one full-width
/// tile). The mosaic always covers the entire space, so it can stand in for a
/// background image rather than sitting on top of one.
///
/// [gutter] and [tileRadius] are what the existing call sites differ on — the
/// games grid butts its covers edge to edge, the carousel insets and rounds
/// them so the montage stays legible at card size — so they are parameters
/// rather than a second implementation.
class CoverMosaic extends StatelessWidget {
  const CoverMosaic({
    super.key,
    required this.covers,
    this.gutter = 0,
    this.tileRadius = 0,
  });

  /// Cover files, most representative first. Only the first four are drawn.
  final List<File> covers;

  /// Space between tiles. Whatever is behind the mosaic shows through it.
  final double gutter;

  /// Corner radius applied to each tile.
  final double tileRadius;

  @override
  Widget build(BuildContext context) {
    final files = covers.length > 4 ? covers.sublist(0, 4) : covers;
    if (files.isEmpty) return const SizedBox.shrink();

    if (files.length == 1) return _tile(files.first);
    if (files.length == 2) return _row(files);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _row(files.sublist(0, 2))),
        if (gutter > 0) SizedBox(height: gutter),
        Expanded(child: _row(files.sublist(2))),
      ],
    );
  }

  /// A single cell, cropped to fill.
  ///
  /// `SizedBox.expand` plus stretch on both axes is load-bearing: inside a Row
  /// the cross axis is loosely constrained, so a bare Image sizes to its
  /// intrinsic aspect ratio and leaves empty bands instead of filling its cell.
  Widget _tile(File file) {
    final image = SizedBox.expand(
      child: Image.file(
        file,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
    if (tileRadius <= 0) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tileRadius),
      child: image,
    );
  }

  Widget _row(List<File> files) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < files.length; i++) ...[
        if (i > 0 && gutter > 0) SizedBox(width: gutter),
        Expanded(child: _tile(files[i])),
      ],
    ],
  );
}

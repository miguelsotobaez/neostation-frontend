import 'package:flutter/material.dart';

enum CarouselPageChangeReason { manual, controller }

class NativeCarousel extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final void Function(int index, CarouselPageChangeReason reason)?
  onPageChanged;
  final ValueChanged<double>? onPageScrolled;
  final int initialIndex;

  /// When non-null, each page is sized so the card can keep its natural
  /// square artwork plus this footer height below it (width = height - footerHeight).
  /// This makes the carousel page match the aspect ratio used by SystemCard in
  /// the grid, where the footer is rendered under the artwork.
  final double? footerHeight;

  const NativeCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.onPageScrolled,
    this.initialIndex = 0,
    this.footerHeight,
  });

  @override
  State<NativeCarousel> createState() => NativeCarouselState();
}

class NativeCarouselState extends State<NativeCarousel> {
  PageController? _pageController;
  int _currentIndex = 0;
  double _lastVpFraction = 0;
  int _lastReportedIndex = 0;
  final ValueNotifier<double> _pageNotifier = ValueNotifier(0.0);
  CarouselPageChangeReason _pageChangeReason =
      CarouselPageChangeReason.controller;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _lastReportedIndex = widget.initialIndex;
    _pageNotifier.value = widget.initialIndex.toDouble();
  }

  @override
  void didUpdateWidget(NativeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex &&
        widget.initialIndex != _currentIndex &&
        _pageController != null) {
      _animateToPage(widget.initialIndex);
    }
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onPageScroll);
    _pageController?.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    final page = _pageController?.page;
    if (page == null) return;

    _pageNotifier.value = page;
    _currentIndex = page.round();
    widget.onPageScrolled?.call(page);

    if (_currentIndex != _lastReportedIndex) {
      final dist = (page - _currentIndex).abs();
      if (dist < 0.05) {
        _lastReportedIndex = _currentIndex;
        final reason = _pageChangeReason;
        _pageChangeReason = CarouselPageChangeReason.controller;
        widget.onPageChanged?.call(_currentIndex, reason);
      }
    }
  }

  void _ensureController(double vpFraction) {
    if (_pageController == null || vpFraction != _lastVpFraction) {
      _pageController?.removeListener(_onPageScroll);
      _pageController?.dispose();
      _lastVpFraction = vpFraction;
      _pageController = PageController(
        viewportFraction: vpFraction,
        initialPage: _currentIndex,
      );
      _pageController!.addListener(_onPageScroll);
      _lastReportedIndex = _currentIndex;
    }
  }

  void nextPage() {
    if (_currentIndex < widget.itemCount - 1) {
      _animateToPage(_currentIndex + 1);
    }
  }

  void previousPage() {
    if (_currentIndex > 0) {
      _animateToPage(_currentIndex - 1);
    }
  }

  void _animateToPage(int index) {
    _pageChangeReason = CarouselPageChangeReason.controller;
    _pageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutQuart,
    );
  }

  void jumpToPage(int index) {
    _pageChangeReason = CarouselPageChangeReason.controller;
    _pageController?.jumpToPage(index);
  }

  void animateToPage(int index) {
    if (index >= 0 && index < widget.itemCount) {
      _animateToPage(index);
    }
  }

  int get currentIndex => _currentIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        final double pageWidth;
        final double pageAspectRatio;
        if (widget.footerHeight != null && widget.footerHeight! > 0) {
          // Match the grid's SystemCard aspect ratio: square artwork plus a
          // footer row below it (page width = page height - footer height).
          pageWidth = (maxHeight - widget.footerHeight!).clamp(0.0, maxHeight);
          pageAspectRatio = maxHeight > 0 ? pageWidth / maxHeight : 1.0;
        } else {
          // Default: square pages that fill the available height.
          pageWidth = maxHeight;
          pageAspectRatio = 1.0;
        }

        final vpFraction = (availableWidth > 0)
            ? (pageWidth / availableWidth).clamp(0.18, 1.0)
            : 0.3;

        _ensureController(vpFraction);

        return SizedBox(
          height: maxHeight,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              _pageChangeReason = CarouselPageChangeReason.manual;
            },
            child: PageView.builder(
              controller: _pageController,
              clipBehavior: Clip.none,
              padEnds: true,
              allowImplicitScrolling: true,
              itemCount: widget.itemCount,
              itemBuilder: (context, index) {
                // Build the card exactly once and pass it as the
                // ValueListenableBuilder's `child`. Only the cheap
                // Opacity/Transform.scale envelope reacts to per-frame page
                // scroll updates — the card subtree (which does disk reads and
                // Image.file decoding) is NOT rebuilt on every scroll frame.
                // RepaintBoundary lets the card's raster be cached and reused
                // as the scale/opacity animate.
                final card = RepaintBoundary(
                  child: AspectRatio(
                    aspectRatio: pageAspectRatio,
                    child: widget.itemBuilder(context, index),
                  ),
                );
                return ValueListenableBuilder<double>(
                  valueListenable: _pageNotifier,
                  child: card,
                  builder: (context, page, child) {
                    final distance = (index - page).abs() - 0.6;
                    final scale = (1.0 - distance * 0.4).clamp(0.25, 1.0);
                    final opacity = (0.6 - distance * 1).clamp(0.1, 1.0);

                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: child,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

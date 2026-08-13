import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/models/my_systems.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/services/music_player_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../themes/corner_radii.dart';
import '../../../themes/chrome_surface.dart';
import '../../../widgets/neo_glass.dart';
import '../../../widgets/shaders/shader_gif_widget.dart';
import '../../../widgets/shaders/music_card_shader_background.dart';
import '../../../utils/image_utils.dart';
import '../../../widgets/system_logo_fallback.dart';
import '../../../utils/game_utils.dart';

/// A premium card component representing a system or a 'Recent Game' entry.
///
/// Supports dynamic background effects (GIFs, Shaders, Music Covers), localized
/// metadata display, and specialized layouts for 'Recent Games'.
class SystemCard extends StatefulWidget {
  const SystemCard({
    super.key,
    required this.info,
    this.onTap,
    this.isSelected = false,
    this.backgroundCacheWidth = 512,
  });

  /// The system or game metadata resolved for this card.
  final SystemInfo info;

  /// Interaction callback for pointer/controller selection.
  final VoidCallback? onTap;

  /// Whether this card currently has visual focus in the grid.
  final bool isSelected;

  /// Decode width for the card's background image. Defaults to 512 (grid
  /// cards); the carousel passes 1024 since its cards are much larger.
  final int backgroundCacheWidth;

  @override
  State<SystemCard> createState() => _SystemCardState();
}

class _SystemCardState extends State<SystemCard> {
  late final FocusNode _focusNode;
  late final GlobalKey _contentStackKey;
  final MusicPlayerService _musicPlayerService = MusicPlayerService();

  /// In-memory cache for resolved ID3v2 album art.
  Uint8List? _resolvedMusicCoverBytes;
  bool _isResolvingMusicCover = false;
  String? _coverResolutionPath;
  String? _lastActiveTrackPath;

  String? _themeBackgroundPath;
  String _lastThemeFolder = '';

  /// Cached wheel file and existence check — computed once, not on every build.
  File? _cachedWheelFile;
  bool _cachedHasWheelFile = false;

  /// Hierarchy for music cover resolution:
  /// Active Instance Art > Cached Resolved Art > Last Known Picture.
  Uint8List? get _musicCoverBytes =>
      _musicPlayerService.activePicture ??
      _resolvedMusicCoverBytes ??
      _musicPlayerService.currentPicture;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(skipTraversal: true);
    _contentStackKey = GlobalKey(
      debugLabel: 'system_card_${widget.info.title}',
    );
    _musicPlayerService.addListener(_handleMusicStateChanged);
    _handleMusicStateChanged();
    _resolveWheelFile();
  }

  void _resolveWheelFile() {
    final customWheelPath = widget.info.customWheelImage;
    if (widget.info.isGame &&
        customWheelPath != null &&
        customWheelPath.isNotEmpty) {
      _cachedWheelFile = File(customWheelPath);
      _cachedHasWheelFile = _cachedWheelFile!.existsSync();
    } else {
      _cachedWheelFile = null;
      _cachedHasWheelFile = false;
    }
  }

  @override
  void didUpdateWidget(SystemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final folderChanged =
        oldWidget.info.folderName != widget.info.folderName ||
        oldWidget.info.primaryFolderName != widget.info.primaryFolderName;
    if (folderChanged) {
      _themeBackgroundPath = null;
      _lastThemeFolder = '';
    }
    if (oldWidget.info.customWheelImage != widget.info.customWheelImage ||
        folderChanged) {
      _resolveWheelFile();
    }
  }

  @override
  void dispose() {
    _musicPlayerService.removeListener(_handleMusicStateChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Synchronizes the card visual state with the global music player state.
  void _handleMusicStateChanged() {
    if (!mounted || widget.info.folderName != 'music') return;

    final activePath = _musicPlayerService.activeTrack?.romPath;
    if (activePath != _lastActiveTrackPath) {
      _lastActiveTrackPath = activePath;
      _coverResolutionPath = null;
      if (_resolvedMusicCoverBytes != null) {
        setState(() {
          _resolvedMusicCoverBytes = null;
        });
      }
    }

    final immediateCover =
        _musicPlayerService.activePicture ?? _musicPlayerService.currentPicture;
    if (immediateCover != null) {
      if (!listEquals(immediateCover, _resolvedMusicCoverBytes)) {
        setState(() {
          _resolvedMusicCoverBytes = immediateCover;
        });
      }
      return;
    }

    if (_musicPlayerService.isPlaying) {
      _tryResolveMusicCover();
      return;
    }

    if (_resolvedMusicCoverBytes != null) {
      setState(() {
        _resolvedMusicCoverBytes = null;
      });
    }
  }

  /// Attempts to extract album art from the filesystem for the current track.
  Future<void> _tryResolveMusicCover() async {
    if (_isResolvingMusicCover) return;

    final path =
        _musicPlayerService.activeTrack?.romPath ??
        _musicPlayerService.currentTrack?.romPath;
    if (path == null || path.isEmpty) return;

    _isResolvingMusicCover = true;
    _coverResolutionPath = path;
    try {
      final bytes = await _musicPlayerService.extractPicture(path);
      if (!mounted) return;
      if (_coverResolutionPath != path) return;
      if (bytes == null) return;
      setState(() {
        _resolvedMusicCoverBytes = bytes;
      });
    } finally {
      _isResolvingMusicCover = false;
    }
  }

  /// Logic check for rendering the specialized music playback background shader.
  bool get _shouldShowMusicPlaybackBackground =>
      widget.info.folderName == 'music' &&
      _musicPlayerService.isPlaying &&
      _musicCoverBytes != null;

  @override
  Widget build(BuildContext context) {
    // Subscribe to theme folder changes — only re-resolve assets when theme actually changes.
    final themeFolder = context.select<NeoAssetsProvider, String>(
      (p) => p.activeThemeFolder,
    );

    if (!widget.info.isGame && themeFolder != _lastThemeFolder) {
      _lastThemeFolder = themeFolder;
      final neoAssets = context.read<NeoAssetsProvider>();
      final folderName =
          widget.info.primaryFolderName ?? widget.info.folderName ?? '';

      _themeBackgroundPath =
          widget.info.customBackgroundPath?.isNotEmpty == true
          ? null
          : neoAssets.getBackgroundForSystemSync(folderName);
    }

    return Padding(
      padding: EdgeInsets.all(2.r),
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: NeoGlass(
          role: GlassSurfaceRole.card,
          // The systems screen can display many cards simultaneously. A
          // BackdropFilter per card was the source of the navigation slowdown,
          // so cards use the lightweight glass path: transparent tint + rim.
          enableBackdropBlur: false,
          showSheen: false,
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
              BorderRadius.circular(14.r),
          child: ClipRRect(
            borderRadius:
                Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                BorderRadius.circular(9.r),
            child: InkWell(
              focusNode: _focusNode,
              onTap: () {
                // A tap on the already-selected card confirms it rather than
                // moving the selection (touch users have no A button), so it
                // earns the enter sound instead of the nav sound.
                if (widget.isSelected) {
                  SfxService().playEnterSound();
                } else {
                  SfxService().playNavSound();
                }
                widget.onTap?.call();
              },
              canRequestFocus: false,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 4.r,
                  bottom: 0.r,
                  left: 4.r,
                  right: 4.r,
                ),
                child: widget.info.isGame
                    ? Column(
                        children: [
                          Expanded(
                            child: Stack(
                              key: _contentStackKey,
                              children: [
                                _buildSystemBackground(),
                                _buildGameMainContent(context),
                              ],
                            ),
                          ),
                          _buildGameFooter(context),
                        ],
                      )
                    : Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                              key: _contentStackKey,
                              children: [_buildSystemBackground()],
                            ),
                          ),
                          _buildSystemFooter(context),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Orchestrates background rendering, selecting between static images,
  /// music cover shaders, or GIF animators.
  Widget _buildSystemBackground() {
    if (widget.info.folderName == 'music') {
      return AnimatedBuilder(
        animation: _musicPlayerService,
        builder: (context, child) {
          if (_shouldShowMusicPlaybackBackground) {
            return Positioned.fill(
              child: MusicCardShaderBackground(
                key: ValueKey(
                  _musicPlayerService.activeTrack?.romPath ??
                      _musicPlayerService.currentTrack?.romPath,
                ),
                coverBytes: _musicCoverBytes!,
                tintColor:
                    widget.info.color1AsColor ??
                    Theme.of(context).colorScheme.primary,
                borderRadius:
                    Theme.of(
                      context,
                    ).extension<CornerRadii>()?.radiusInternalRadius ??
                    12.r,
                opacity: 1.0,
              ),
            );
          }

          return _buildDefaultSystemBackground();
        },
      );
    }

    return _buildDefaultSystemBackground();
  }

  /// Standard background resolution logic for all system cards.
  Widget _buildDefaultSystemBackground() {
    final customBgPath = widget.info.customBackgroundPath;
    final hasCustomBg = customBgPath != null && customBgPath.isNotEmpty;

    // SCENARIO A: Animated GIF (custom or theme-provided).
    if (hasCustomBg && ImageUtils.isGif(customBgPath)) {
      return Positioned.fill(
        child: ClipRRect(
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
              BorderRadius.circular(9.r),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: ShaderGifWidget(
              imagePath: customBgPath,
              key: ValueKey('${customBgPath}_${widget.info.imageVersion}'),
            ),
          ),
        ),
      );
    }

    // SCENARIO B: Animated GIF from theme.
    if (!hasCustomBg && ImageUtils.isGif(_themeBackgroundPath)) {
      return Positioned.fill(
        child: ClipRRect(
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
              BorderRadius.circular(9.r),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: ShaderGifWidget(
              imagePath: _themeBackgroundPath!,
              key: ValueKey(
                '${_themeBackgroundPath}_${widget.info.imageVersion}',
              ),
            ),
          ),
        ),
      );
    }

    // SCENARIO C: Static image (Custom or Theme-provided).
    final activeBgPath = hasCustomBg ? customBgPath : _themeBackgroundPath;
    final hasActiveBg = activeBgPath != null && activeBgPath.isNotEmpty;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius:
            Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
            BorderRadius.circular(9.r),
        child: hasActiveBg
            ? Image.file(
                File(activeBgPath),
                key: ValueKey('${activeBgPath}_${widget.info.imageVersion}'),
                fit: BoxFit.cover,
                cacheWidth: widget.backgroundCacheWidth,
                errorBuilder: (context, error, stackTrace) => Stack(
                  children: [
                    Container(color: Colors.transparent),
                    Container(
                      color: widget.info.color1AsColor?.withValues(alpha: 0.26),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Container(color: Colors.transparent),
                  Container(
                    color: widget.info.color1AsColor?.withValues(alpha: 0.26),
                  ),
                ],
              ),
      ),
    );
  }

  /// Helper for localized play time formatting.
  String _formatPlayTimeLocalized(int seconds) {
    return GameUtils.formatPlayTime(
      seconds,
      fullWords: true,
      hourLabel: AppLocale.hour.getString(context),
      hoursLabel: AppLocale.hours.getString(context),
      minuteLabel: AppLocale.minute.getString(context),
      minutesLabel: AppLocale.minutes.getString(context),
      secondLabel: AppLocale.second.getString(context),
      secondsLabel: AppLocale.seconds.getString(context),
    );
  }

  /// Renders the system brand logo with fallback support.
  /// The white-transparent logo is tinted with [color] (falls back to theme text).
  Widget _buildSystemLogo(
    String assetLogoPath, {
    double? height,
    Color? color,
  }) {
    final customLogoPath = widget.info.customLogoPath;
    final hasCustomLogo = customLogoPath != null && customLogoPath.isNotEmpty;

    Widget buildLogo(Widget image) {
      if (color == null) return image;
      return ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: image,
      );
    }

    if (hasCustomLogo) {
      return buildLogo(
        Image.file(
          File(customLogoPath),
          key: ValueKey('${customLogoPath}_${widget.info.imageVersion}'),
          height: height ?? 32.r,
          cacheWidth: 256,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            assetLogoPath,
            height: height,
            cacheWidth: 256,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => SystemLogoFallback(
              title: widget.info.title,
              shortName: widget.info.shortName,
              height: height ?? 32.r,
            ),
          ),
        ),
      );
    }

    return buildLogo(
      Image.asset(
        assetLogoPath,
        height: height ?? 32.r,
        cacheWidth: 256,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SystemLogoFallback(
          title: widget.info.title,
          shortName: widget.info.shortName,
          height: height ?? 32.r,
        ),
      ),
    );
  }

  /// Builds the foreground content for game cards, including the RECENT badge
  /// and the game wheel/logo.
  Widget _buildGameMainContent(BuildContext context) {
    return Stack(
      children: [
        // RECENT badge.
        Positioned(
          top: 6.r,
          right: 6.r,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                  BorderRadius.circular(9.r),
            ),
            child: Text(
              AppLocale.recentBadge.getString(context),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondary,
                fontSize: 8.r,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),

        // Central game wheel/logo.
        Center(
          child: !_cachedHasWheelFile
              ? const SizedBox.shrink()
              : Container(
                  padding: EdgeInsetsGeometry.all(48.r),
                  child: Image.file(
                    _cachedWheelFile!,
                    height: 256.r,
                    fit: BoxFit.contain,
                    cacheWidth: 512,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
        ),
      ],
    );
  }

  /// Renders a footer for game cards, matching the system card footer style.
  Widget _buildGameFooter(BuildContext context) {
    return Container(
      height: 32.r,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 8.r),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            AppLocale.timePlayedLabel
                .getString(context)
                .replaceFirst(
                  '{time}',
                  _formatPlayTimeLocalized(
                    widget.info.gameModel?.playTime ?? 0,
                  ),
                )
                .toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10.r,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a bottom footer with the system logo for non-game system cards.
  ///
  /// The footer expands to fill the remaining space below the square artwork,
  /// and the logo is auto-sized to fit while keeping its aspect ratio.
  Widget _buildSystemFooter(BuildContext context) {
    final assetLogoPath = _resolveSystemLogoPath();

    return Expanded(
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.only(top: 1.r, bottom: 1.r, left: 2.r, right: 2.r),
        child: FittedBox(
          fit: BoxFit.contain,
          child: _buildSystemLogo(
            assetLogoPath,
            height: 128.r,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Resolves the logo asset path for this system.
  String _resolveSystemLogoPath() {
    final resolvedLogoFolder = widget.info.primaryFolderName?.isNotEmpty == true
        ? widget.info.primaryFolderName!
        : (widget.info.folderName?.isNotEmpty == true
              ? widget.info.folderName!
              : 'all');
    return 'assets/images/logos/$resolvedLogoFolder.webp';
  }
}

/// A utilitarian linear progress indicator.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, this.color, required this.percentage});

  final Color? color;
  final int? percentage;

  @override
  Widget build(BuildContext context) {
    final progressColor = color ?? Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 5.r,
          decoration: BoxDecoration(
            color: progressColor.withValues(alpha: 0.1),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Container(
            width: constraints.maxWidth * (percentage! / 100),
            height: 5.r,
            decoration: BoxDecoration(color: progressColor),
          ),
        ),
      ],
    );
  }
}

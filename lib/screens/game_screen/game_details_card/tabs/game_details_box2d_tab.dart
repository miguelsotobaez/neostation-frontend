import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../models/system_model.dart';
import '../../../../models/game_model.dart';
import '../../../../providers/file_provider.dart';
import '../../../../themes/corner_radii.dart';

class GameDetailsBox2dTab extends StatefulWidget {
  final SystemModel system;
  final GameModel game;
  final FileProvider fileProvider;

  /// Bumped when a scrape rewrites the artwork. It keys the image so a
  /// re-scraped box art is resolved again instead of being redrawn from the
  /// copy this widget already holds.
  final int imageVersion;

  const GameDetailsBox2dTab({
    super.key,
    required this.system,
    required this.game,
    required this.fileProvider,
    this.imageVersion = 0,
  });

  @override
  State<GameDetailsBox2dTab> createState() => _GameDetailsBox2dTabState();
}

class _GameDetailsBox2dTabState extends State<GameDetailsBox2dTab> {
  double _imageAspectRatio = 3 / 4;

  ImageStream? _currentImageStream;
  ImageStreamListener? _currentImageListener;

  void _loadImageAspectRatio(String path) {
    if (path.isEmpty) return;

    final File file = File(path);
    if (!file.existsSync()) return;

    _removeImageListener();

    final Image image = Image.file(file);
    final ImageStream stream = image.image.resolve(const ImageConfiguration());

    final listener = ImageStreamListener((
      ImageInfo info,
      bool synchronousCall,
    ) {
      if (!mounted) return;
      final double aspectRatio = info.image.width / info.image.height;
      if (aspectRatio <= 0) return;

      void update() {
        setState(() {
          _imageAspectRatio = aspectRatio;
        });
      }

      if (synchronousCall) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) update();
        });
      } else {
        update();
      }
    });

    stream.addListener(listener);
    _currentImageStream = stream;
    _currentImageListener = listener;
  }

  void _removeImageListener() {
    if (_currentImageStream != null && _currentImageListener != null) {
      _currentImageStream!.removeListener(_currentImageListener!);
      _currentImageStream = null;
      _currentImageListener = null;
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageSystemFolder = widget.system.primaryFolderName;
    final box2dPath = widget.game.getImagePath(
      imageSystemFolder,
      'box2d',
      widget.fileProvider,
    );
    final box2dExists = File(box2dPath).existsSync();

    if (box2dExists) {
      _loadImageAspectRatio(box2dPath);
    }

    return Positioned(
      left: 12.r,
      right: 12.r,
      top: 55.r,
      bottom: 110.r,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            borderRadius:
                Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.3),
                blurRadius: 3.r,
                offset: Offset(3.0.r, 3.0.r),
              ),
            ],
            color: Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius:
                Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                BorderRadius.circular(14.r),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: _imageAspectRatio,
              child: box2dExists
                  ? Image.file(
                      File(box2dPath),
                      key: ValueKey(
                        'box2d_${widget.game.romPath ?? widget.game.romname}'
                        '_v${widget.imageVersion}',
                      ),
                      fit: BoxFit.contain,
                      cacheWidth: 640,
                    )
                  : Center(
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 48.r,
                        color: Colors.white24,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

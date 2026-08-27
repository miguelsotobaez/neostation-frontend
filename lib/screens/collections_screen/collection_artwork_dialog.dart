import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/repositories/collection_repository.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/themes/corner_radii.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/tv_directory_picker.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

/// Dialog allowing users to configure custom background and logo images for a collection.
class CollectionArtworkDialog extends StatefulWidget {
  final CollectionModel collection;
  final VoidCallback? onUpdated;

  const CollectionArtworkDialog({
    super.key,
    required this.collection,
    this.onUpdated,
  });

  static Future<void> show({
    required BuildContext context,
    required CollectionModel collection,
    VoidCallback? onUpdated,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          CollectionArtworkDialog(collection: collection, onUpdated: onUpdated),
    );
  }

  @override
  State<CollectionArtworkDialog> createState() =>
      _CollectionArtworkDialogState();
}

class _CollectionArtworkDialogState extends State<CollectionArtworkDialog> {
  late CollectionModel _collection;
  int _selectedIndex = 0; // 0 = Background, 1 = Logo
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _collection = widget.collection;
    _setupGamepad();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        if (_selectedIndex > 0) {
          setState(() => _selectedIndex = 0);
          SfxService().playNavSound();
        }
      },
      onNavigateDown: () {
        if (_selectedIndex < 1) {
          setState(() => _selectedIndex = 1);
          SfxService().playNavSound();
        }
      },
      onSelectItem: () {
        if (_selectedIndex == 0) {
          _pickAndSaveBackground();
        } else {
          _pickAndSaveLogo();
        }
      },
      onXButton: () {
        if (_selectedIndex == 0 &&
            _collection.customBackgroundPath?.isNotEmpty == true) {
          _resetBackground();
        } else if (_selectedIndex == 1 &&
            _collection.customLogoPath?.isNotEmpty == true) {
          _resetLogo();
        }
      },
      onBack: () {
        SfxService().playBackSound();
        Navigator.of(context).pop();
      },
    );
    _gamepadNav.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GamepadNavigationManager.pushLayer(
        'collection_artwork_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
        modal: true,
      );
    });
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    GamepadNavigationManager.popLayer('collection_artwork_dialog');
    super.dispose();
  }

  Future<void> _pickAndSaveBackground() async {
    try {
      String? pickedPath;

      if (Platform.isAndroid && await PermissionService.isTelevision()) {
        if (!mounted) return;
        pickedPath = await TvDirectoryPicker.showFilePicker(
          context,
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        );
      } else {
        final result = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          dialogTitle: 'Select Collection Background Image',
          windowsOptions: const WindowsOptions(lockParentWindow: true),
          linuxOptions: const LinuxOptions(lockParentWindow: true),
        );
        pickedPath = result?.path;
      }

      if (pickedPath == null || !mounted) return;

      final originalFile = File(pickedPath);
      if (!originalFile.existsSync()) return;

      final extension = path.extension(originalFile.path);
      final fileName = 'collection_${_collection.id}_background$extension';

      final userDataPath = await ConfigService.getUserDataPath();
      final targetDir = Directory(
        path.join(userDataPath, 'media', 'collections'),
      );
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      final targetPath = path.join(targetDir.path, fileName);

      await originalFile.copy(targetPath);

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      await CollectionRepository.setCustomImages(
        _collection.id,
        backgroundPath: targetPath,
      );

      setState(() {
        _collection = _collection.copyWith(
          customBackgroundPath: targetPath,
          imageVersion: _collection.imageVersion + 1,
        );
      });

      if (mounted) {
        final provider = context.read<CollectionProvider>();
        await provider.loadCollections();
        widget.onUpdated?.call();
        if (!mounted) return;
        AppNotification.showNotification(
          context,
          AppLocale.imageUpdatedSuccess.getString(context),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          '${AppLocale.errorUpdatingImage.getString(context)}: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _resetBackground() async {
    try {
      await CollectionRepository.setCustomImages(
        _collection.id,
        backgroundPath: '',
      );

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      setState(() {
        _collection = _collection.copyWith(
          customBackgroundPath: '',
          imageVersion: _collection.imageVersion + 1,
        );
      });

      if (mounted) {
        final provider = context.read<CollectionProvider>();
        await provider.loadCollections();
        widget.onUpdated?.call();
        if (!mounted) return;
        AppNotification.showNotification(
          context,
          AppLocale.imageResetDefault.getString(context),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          '${AppLocale.errorResettingImage.getString(context)}: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _pickAndSaveLogo() async {
    try {
      String? pickedPath;

      if (Platform.isAndroid && await PermissionService.isTelevision()) {
        if (!mounted) return;
        pickedPath = await TvDirectoryPicker.showFilePicker(
          context,
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        );
      } else {
        final result = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          dialogTitle: 'Select Collection Logo Image',
          windowsOptions: const WindowsOptions(lockParentWindow: true),
          linuxOptions: const LinuxOptions(lockParentWindow: true),
        );
        pickedPath = result?.path;
      }

      if (pickedPath == null || !mounted) return;

      final originalFile = File(pickedPath);
      if (!originalFile.existsSync()) return;

      final extension = path.extension(originalFile.path);
      final fileName = 'collection_${_collection.id}_logo$extension';

      final userDataPath = await ConfigService.getUserDataPath();
      final targetDir = Directory(
        path.join(userDataPath, 'media', 'collections'),
      );
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      final targetPath = path.join(targetDir.path, fileName);

      await originalFile.copy(targetPath);

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      await CollectionRepository.setCustomImages(
        _collection.id,
        logoPath: targetPath,
      );

      setState(() {
        _collection = _collection.copyWith(
          customLogoPath: targetPath,
          imageVersion: _collection.imageVersion + 1,
        );
      });

      if (mounted) {
        final provider = context.read<CollectionProvider>();
        await provider.loadCollections();
        widget.onUpdated?.call();
        if (!mounted) return;
        AppNotification.showNotification(
          context,
          AppLocale.imageUpdatedSuccess.getString(context),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          '${AppLocale.errorUpdatingImage.getString(context)}: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _resetLogo() async {
    try {
      await CollectionRepository.setCustomImages(_collection.id, logoPath: '');

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      setState(() {
        _collection = _collection.copyWith(
          customLogoPath: '',
          imageVersion: _collection.imageVersion + 1,
        );
      });

      if (mounted) {
        final provider = context.read<CollectionProvider>();
        await provider.loadCollections();
        widget.onUpdated?.call();
        if (!mounted) return;
        AppNotification.showNotification(
          context,
          AppLocale.imageResetDefault.getString(context),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          '${AppLocale.errorResettingImage.getString(context)}: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.2),
          width: 1.r,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520.w),
        child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Symbols.palette_rounded,
                    color: primaryColor,
                    size: 24.r,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _collection.name,
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.titleLarge?.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          AppLocale.systemImages.getString(context),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      SfxService().playBackSound();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              // Background Item
              _buildArtworkRow(
                index: 0,
                title: AppLocale.backgroundImage.getString(context),
                subtitle: AppLocale.backgroundImageSubtitle.getString(context),
                imagePath: _collection.customBackgroundPath ?? '',
                onPick: _pickAndSaveBackground,
                onReset: _resetBackground,
              ),
              SizedBox(height: 12.h),

              // Logo Item
              _buildArtworkRow(
                index: 1,
                title: AppLocale.logoImage.getString(context),
                subtitle: AppLocale.logoImageSubtitle.getString(context),
                imagePath: _collection.customLogoPath ?? '',
                onPick: _pickAndSaveLogo,
                onReset: _resetLogo,
              ),
              SizedBox(height: 20.h),

              // Footer info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pick: [A]  •  Reset: [X]  •  Back: [B]',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      SfxService().playBackSound();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 10.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtworkRow({
    required int index,
    required String title,
    required String subtitle,
    required String imagePath,
    required VoidCallback onPick,
    required VoidCallback onReset,
  }) {
    final isFocused = _selectedIndex == index;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();

    return InkWell(
      onTap: () {
        setState(() => _selectedIndex = index);
        onPick();
      },
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: isFocused
              ? primaryColor.withValues(alpha: 0.12)
              : theme.cardColor.withValues(alpha: 0.4),
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
              BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused
                ? primaryColor
                : theme.dividerColor.withValues(alpha: 0.2),
            width: isFocused ? 2.r : 1.r,
          ),
        ),
        child: Row(
          children: [
            // Preview
            Container(
              key: ValueKey('${imagePath}_${_collection.imageVersion}'),
              width: 56.r,
              height: 56.r,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: hasImage
                  ? Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) => Icon(
                        Symbols.broken_image_rounded,
                        size: 24.r,
                        color: Colors.white54,
                      ),
                    )
                  : Icon(
                      Symbols.image_not_supported_rounded,
                      size: 24.r,
                      color: Colors.white38,
                    ),
            ),
            SizedBox(width: 14.w),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: isFocused
                          ? primaryColor
                          : theme.textTheme.titleMedium?.color,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (hasImage) ...[
                    SizedBox(height: 4.h),
                    Text(
                      path.basename(imagePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: primaryColor.withValues(alpha: 0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),

            // Action buttons
            if (hasImage)
              IconButton(
                tooltip: 'Reset to Default',
                onPressed: onReset,
                icon: const Icon(
                  Symbols.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ElevatedButton.icon(
              onPressed: onPick,
              icon: const Icon(Symbols.file_upload_rounded, size: 16),
              label: const Text('Browse'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                textStyle: TextStyle(fontSize: 12.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

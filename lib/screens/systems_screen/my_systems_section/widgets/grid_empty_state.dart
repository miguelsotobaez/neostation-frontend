import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/sfx_service.dart';
import '../../../../providers/sqlite_config_provider.dart';

/// Renders the 'Empty State' view with a clear CTA for library configuration.
///
/// Extracted verbatim from `MySystems._buildEmptyState` so the systems grid
/// host stays lean; behavior and layout are unchanged. The [configProvider] is
/// passed in (already read by the host) rather than re-resolved here.
class GridEmptyState extends StatelessWidget {
  const GridEmptyState({super.key, required this.configProvider});

  final SqliteConfigProvider configProvider;

  /// Handles the "select ROM folder" tap. On iOS there's no external folder
  /// picker (see [SqliteConfigScanning.selectRomFolder]) — the app always
  /// uses its own internal `Documents/roms` folder. That's invisible to the
  /// user unless we tell them, so after the provider call we show exactly
  /// where that folder lives and how to put ROMs into it via the Files app.
  Future<void> _handleSelectFolderTap(
    BuildContext context,
    SqliteConfigProvider configProvider,
  ) async {
    await configProvider.selectRomFolder(context: context);
    if (!Platform.isIOS || !context.mounted) return;

    final romsFolder = await ConfigService.getDefaultIOSRomsFolder();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add your ROMs'),
        content: SingleChildScrollView(
          child: Text(
            'NeoStation looks for games in its own folder:\n\n'
            '$romsFolder\n\n'
            'To add games: open the Files app on this iPhone, go to '
            '"On My iPhone" (or "On My iPad") > "NeoStation" > "roms", and '
            'copy your game files in there — organized into subfolders per '
            'system (e.g. "snes", "gba", "psx"). You can also drag files in '
            'from a computer via Finder or iTunes file sharing.\n\n'
            'Once your files are in place, tap this button again to scan '
            'for them.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image.asset(
                  'assets/images/icons/folder-add-bulk.png',
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              configProvider.hasRomFolders
                  ? AppLocale.noSystemsFoundTitle.getString(context)
                  : AppLocale.welcomeNeoStation.getString(context),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              configProvider.hasRomFolders
                  ? AppLocale.noSystemsFoundDesc.getString(context)
                  : AppLocale.selectRomFolderDescShort.getString(context),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Primary Call to Action Button.
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8.r),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  canRequestFocus: false,
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(8.r),
                  onTap: () {
                    SfxService().playEnterSound();
                    _handleSelectFolderTap(context, configProvider);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Symbols.folder_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocale.selectRomFolderButton.getString(context),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:provider/provider.dart';
import '../../../../models/system_model.dart';
import '../../../../models/game_model.dart';
import '../../../../providers/file_provider.dart';
import '../../../../providers/sqlite_config_provider.dart';
import '../../../../services/screenscraper_service.dart';
import '../../../../themes/corner_radii.dart';
import '../../../../themes/chrome_surface.dart';
import '../../../../widgets/neo_glass.dart';
import '../../../../utils/game_utils.dart';
import '../widgets/scrolling_description_text.dart';

class GameDetailsGameInfoTab extends StatelessWidget {
  final SystemModel system;
  final GameModel game;
  final FileProvider fileProvider;
  final String description;

  /// Hides the metadata pills while the card's scrape panel covers this tab.
  final bool isScrapingGame;
  final VoidCallback onScrapeGame;

  const GameDetailsGameInfoTab({
    super.key,
    required this.system,
    required this.game,
    required this.fileProvider,
    required this.description,
    required this.isScrapingGame,
    required this.onScrapeGame,
  });

  /// ScreenScraper uses a few language identifiers that differ from the
  /// interface language codes used by NeoStation.
  String _descriptionLanguageForAppLanguage(String appLanguage) {
    switch (appLanguage) {
      case 'ja':
        return 'jp';
      case 'zh_Hant':
        // ScreenScraper does not expose a separate Traditional Chinese
        // description slot in NeoStation's current metadata model.
        return 'zh';
      case 'id':
        // Indonesian descriptions are not currently stored by the scraper.
        return 'en';
      default:
        return appLanguage;
    }
  }

  /// Returns only the description matching NeoStation's selected UI language.
  /// If that translation does not exist, English is the sole fallback so the
  /// UI never silently switches to another unrelated language.
  String _descriptionForAppLanguage(BuildContext context) {
    final appLanguage = context
        .watch<SqliteConfigProvider>()
        .config
        .appLanguage;
    final descriptionLanguage = _descriptionLanguageForAppLanguage(appLanguage);
    final descriptions = game.descriptions;

    if (descriptions == null || descriptions.isEmpty) return '';

    final preferred = descriptions[descriptionLanguage]?.trim() ?? '';
    if (preferred.isNotEmpty) return preferred;

    if (descriptionLanguage != 'en') {
      final english = descriptions['en']?.trim() ?? '';
      if (english.isNotEmpty) return english;
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final activeDescription = _descriptionForAppLanguage(context);
    final bool showScrapeView = activeDescription.isEmpty;

    return Positioned(
      // Keep the panel comfortably inside the iPhone landscape viewport instead
      // of stretching almost edge-to-edge across the details area.
      left: 18.r,
      right: 18.r,
      top: 58.r,
      bottom: 128.r,
      child: NeoGlass(
        role: GlassSurfaceRole.panel,
        borderRadius:
            Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
            BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: 0.22),
            blurRadius: 3.r,
            offset: Offset(2.0.r, 2.0.r),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(10.r, 8.r, 10.r, 0.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.description_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 13.r,
                      ),
                      SizedBox(width: 6.r),
                      Text(
                        AppLocale.gameInfo.getString(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 10.r),
                      if (!showScrapeView &&
                          !isScrapingGame &&
                          (game.developer.isNotEmpty ||
                              game.players.isNotEmpty ||
                              game.year.isNotEmpty))
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (game.developer.isNotEmpty)
                                    _InfoPill(
                                      icon: Symbols.business_rounded,
                                      text: game.developer,
                                    ),
                                  if (game.players.isNotEmpty)
                                    _InfoPill(
                                      icon: Symbols.people_rounded,
                                      text: game.players,
                                    ),
                                  if (game.year.isNotEmpty)
                                    _InfoPill(
                                      icon: Symbols.calendar_today_rounded,
                                      text:
                                          RegExp(
                                            r'\d{4}',
                                          ).stringMatch(game.year) ??
                                          game.year,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    height: 10.r,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(10.r, 4.r, 10.r, 10.r),
                child: showScrapeView
                    ? _buildNonScrapedView(context)
                    : _buildScrapedView(context, activeDescription),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNonScrapedView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocale.incompleteMetadata.getString(context),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18.r,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.r),
          SizedBox(
            width: 300.r,
            child: Text(
              AppLocale.scrapeToDownload.getString(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 11.r,
                height: 1.4,
              ),
            ),
          ),
          SizedBox(height: 16.r),
          FutureBuilder<bool>(
            future: ScreenScraperService.hasSavedCredentials(),
            builder: (context, snapshot) {
              if (system.folderName == 'android-apps') {
                return Text(
                  AppLocale.scrapingUnavailableAndroid.getString(context),
                  style: TextStyle(fontSize: 10.r, color: Colors.grey),
                );
              }
              final hasCredentials = snapshot.data ?? false;
              if (!hasCredentials) {
                return Text(
                  AppLocale.loginToScrape.getString(context),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 10.r,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScrapedView(BuildContext context, String activeDescription) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.r),
      child: ScrollingDescriptionText(
        text: GameUtils.cleanupDescription(activeDescription),
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.82),
          fontSize: 11.r,
          height: 1.55,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.r),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10.r,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          SizedBox(width: 4.r),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.r,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

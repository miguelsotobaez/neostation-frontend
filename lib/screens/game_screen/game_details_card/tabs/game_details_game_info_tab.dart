import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import '../../../../models/system_model.dart';
import '../../../../models/game_model.dart';
import '../../../../providers/file_provider.dart';
import '../../../../services/screenscraper_service.dart';
import '../../../../themes/corner_radii.dart';
import '../../../../utils/game_utils.dart';
import '../widgets/scrolling_description_text.dart';

class GameDetailsGameInfoTab extends StatefulWidget {
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

  @override
  State<GameDetailsGameInfoTab> createState() => _GameDetailsGameInfoTabState();
}

class _GameDetailsGameInfoTabState extends State<GameDetailsGameInfoTab> {
  static const List<String> _languageLabels = [
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'jp',
    'ko',
    'ru',
    'zh',
    'nl',
    'sv',
    'da',
    'fi',
    'no',
    'pl',
    'hu',
    'cs',
    'ro',
  ];

  static const Map<String, String> _languageNames = {
    'en': 'English',
    'es': 'Espanol',
    'fr': 'Francais',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Portugues',
    'jp': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
    'nl': 'Nederlands',
    'sv': 'Svenska',
    'da': 'Dansk',
    'fi': 'Suomi',
    'no': 'Norsk',
    'pl': 'Polski',
    'hu': 'Magyar',
    'cs': 'Cesky',
    'ro': 'Romanian',
  };

  String _selectedLanguage = 'en';

  List<String> _availableLanguages() {
    final descriptions = widget.game.descriptions;
    if (descriptions == null || descriptions.isEmpty) return [];
    return _languageLabels
        .where(
          (lang) =>
              descriptions[lang] != null && descriptions[lang]!.isNotEmpty,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.description;

    final bool showScrapeView =
        description.isEmpty ||
        description == AppLocale.noDescription.getString(context) ||
        description.trim().isEmpty;

    return Positioned(
      left: 12.r,
      right: 12.r,
      top: 55.r,
      bottom: 110.r,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
              BorderRadius.circular(14.r),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1.r,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.25),
              blurRadius: 2.r,
              offset: Offset(2.0.r, 2.0.r),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8.r, 8.r, 8.r, 0.r),
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
                      const Spacer(),
                      if (!showScrapeView &&
                          !widget.isScrapingGame &&
                          (widget.game.developer.isNotEmpty ||
                              widget.game.players.isNotEmpty ||
                              widget.game.year.isNotEmpty))
                        Row(
                          children: [
                            if (widget.game.developer.isNotEmpty)
                              _InfoPill(
                                icon: Symbols.business_rounded,
                                text: widget.game.developer,
                              ),
                            if (widget.game.players.isNotEmpty)
                              _InfoPill(
                                icon: Symbols.people_rounded,
                                text: widget.game.players,
                              ),
                            if (widget.game.year.isNotEmpty)
                              _InfoPill(
                                icon: Symbols.calendar_today_rounded,
                                text:
                                    RegExp(
                                      r'\d{4}',
                                    ).stringMatch(widget.game.year) ??
                                    widget.game.year,
                              ),
                          ],
                        ),
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
                padding: EdgeInsets.all(8.r),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // While scraping, the card lays ScrapingProgressPanel over
                    // this whole region — every tab gets the same feedback, so
                    // this tab no longer draws its own copy.
                    return showScrapeView
                        ? _buildNonScrapedView()
                        : _buildScrapedView();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNonScrapedView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocale.incompleteMetadata.getString(context),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20.r,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12.r),
          SizedBox(
            width: 300.r,
            child: Text(
              AppLocale.scrapeToDownload.getString(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12.r,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: 32.r),
          FutureBuilder<bool>(
            future: ScreenScraperService.hasSavedCredentials(),
            builder: (context, snapshot) {
              if (widget.system.folderName == 'android-apps') {
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

  Widget _buildScrapedView() {
    final availableLanguages = _availableLanguages();

    if (availableLanguages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(12.r),
          child: ScrollingDescriptionText(
            text: GameUtils.cleanupDescription(widget.description),
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.8),
              fontSize: 11.r,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    final activeDesc = widget.game.getDescriptionForLanguage(_selectedLanguage);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.r),
            child: ScrollingDescriptionText(
              text: GameUtils.cleanupDescription(
                activeDesc.isNotEmpty ? activeDesc : widget.description,
              ),
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 11.r,
                height: 1.6,
              ),
            ),
          ),
        ),
        if (availableLanguages.length > 1)
          Container(
            height: 28.r,
            margin: EdgeInsets.only(bottom: 4.r),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 8.r),
              itemCount: availableLanguages.length,
              separatorBuilder: (_, _) => SizedBox(width: 4.r),
              itemBuilder: (context, index) {
                final lang = availableLanguages[index];
                final isSelected = lang == _selectedLanguage;
                return Material(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6.r),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang;
                      });
                    },
                    borderRadius: BorderRadius.circular(6.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.r,
                        vertical: 4.r,
                      ),
                      child: Text(
                        _languageNames[lang] ?? lang.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 9.r,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
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

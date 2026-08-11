import 'package:flutter/material.dart';
import '../screens/scraper_screen/new_scraper_options_screen.dart';

/// Hosts the scraper options screen unconditionally: ScreenScraper login is
/// only one of several independent scraper sources here (alongside
/// SteamGridDB and HowLongToBeat, neither of which need an account), so
/// missing ScreenScraper credentials must not block the whole section — only
/// the screen's own "Account" tab cares about login state.
class ScraperContent extends StatelessWidget {
  const ScraperContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const NewScraperOptionsScreen();
  }
}

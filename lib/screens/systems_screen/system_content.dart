import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/theme_provider.dart';
import '../../../providers/sqlite_config_provider.dart';
import 'my_systems_section/my_systems_grid.dart';
import 'my_systems_section/initial_setup_widget.dart';

/// Orchestrator for the 'Systems' tab content.
///
/// Manages the visual state transition between the initial scanning/loading phase,
/// the setup wizard for first-time users, and the primary system library grid.
class SystemContent extends StatelessWidget {
  const SystemContent({super.key, this.selectedIndex = 0, this.onCardTapped});

  /// Index of the currently selected system card within the grid.
  final int selectedIndex;

  /// Callback invoked when a system card is interactively selected.
  final Function(int index)? onCardTapped;

  @override
  Widget build(BuildContext context) {
    return Consumer2<SqliteConfigProvider, ThemeProvider>(
      builder: (context, configProvider, themeProvider, child) {
        // Determine the current operational state of the library.
        final isLoading = configProvider.isLoading || configProvider.isScanning;

        // Show setup wizard if scan is finished but no systems were resolved.
        final showInitialSetup =
            !isLoading &&
            !configProvider.hasDetectedSystems &&
            configProvider.scanCompleted;

        // Show primary library content only when initialization and scanning are complete.
        final showContent =
            !isLoading && configProvider.scanCompleted && !showInitialSetup;

        return Stack(
          children: [
            // PHASE 1: Loading and Initialization.
            // Displays a progress indicator and status updates for the background ROM scan.
            if (isLoading)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        configProvider.isLoading
                            ? AppLocale.applyingInitialConfig.getString(context)
                            : AppLocale.scanningSystemsRoms.getString(context),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      if (configProvider.isScanning) ...[
                        const SizedBox(height: 16),
                        Text(
                          AppLocale.percentageCompleted
                              .getString(context)
                              .replaceFirst(
                                '{percentage}',
                                (configProvider.scanProgress * 100)
                                    .toInt()
                                    .toString(),
                              ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: configProvider.scanProgress,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          configProvider.scanStatus,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // PHASE 2: First-Run Experience / Initial Setup.
            if (showInitialSetup) InitialSetupWidget(),

            // PHASE 3: Primary System Library.
            if (showContent)
              MySystems(
                selectedIndex: selectedIndex,
                onCardTapped: onCardTapped,
              ),
          ],
        );
      },
    );
  }
}

part of '../system_emulator_settings_dialog.dart';

/// Read-only historical and technical profile for the selected system.
///
/// Hardware facts and representative game titles live alongside each system
/// definition in `assets/systems/*.json` under `system.details`. User-facing
/// prose remains in NeoStation's localization layer, so the same structured
/// profile is rendered in the language selected by the user without duplicating
/// long translated descriptions in every system definition.
extension _SystemInfoTab on _SystemEmulatorSettingsDialogState {
  Widget _buildSystemInfoTab() {
    return FutureBuilder<SystemInfoProfile?>(
      future: SystemInfoCatalog.profileFor(_system.folderName),
      builder: (context, snapshot) {
        return _buildSystemInfoContent(snapshot.data);
      },
    );
  }

  Widget _buildSystemInfoContent(SystemInfoProfile? profile) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeLabel = _localizedSystemType(_system.type);
    final year = _systemYear;
    final hasManufacturer = _system.manufacturer?.trim().isNotEmpty ?? false;
    final manufacturer = hasManufacturer
        ? _system.manufacturer!.trim()
        : AppLocale.unknown.getString(context);
    final architecture = (profile?.architecture ?? '').trim();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12.r, 10.r, 12.r, 12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _systemInfoIdentity(theme, scheme),
          SizedBox(height: 9.r),
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = 6.r;
              final columns = constraints.maxWidth >= 620.r ? 4 : 2;
              final cellWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final metrics = <Widget>[
                _systemInfoMetric(
                  width: cellWidth,
                  icon: Icons.business_rounded,
                  label: AppLocale.manufacturer.getString(context),
                  value: manufacturer,
                ),
                _systemInfoMetric(
                  width: cellWidth,
                  icon: Icons.calendar_month_rounded,
                  label: AppLocale.releaseYear.getString(context),
                  value: year,
                ),
                _systemInfoMetric(
                  width: cellWidth,
                  icon: Icons.category_rounded,
                  label: AppLocale.systemType.getString(context),
                  value: typeLabel,
                ),
              ];
              if (architecture.isNotEmpty) {
                metrics.add(
                  _systemInfoMetric(
                    width: cellWidth,
                    icon: Icons.memory_rounded,
                    label: AppLocale.systemArchitecture.getString(context),
                    value: architecture,
                  ),
                );
              }
              return Wrap(spacing: gap, runSpacing: gap, children: metrics);
            },
          ),
          SizedBox(height: 9.r),

          _systemInfoSection(
            icon: Icons.info_outline_rounded,
            title: AppLocale.description.getString(context),
            child: Text(
              _buildDetailedSummary(
                profile: profile,
                typeLabel: typeLabel,
                manufacturer: manufacturer,
                hasManufacturer: hasManufacturer,
                year: year,
              ),
              style: TextStyle(
                fontSize: 9.5.r,
                height: 1.48,
                color: scheme.onSurface.withValues(alpha: 0.84),
              ),
            ),
          ),

          if (_hasTechnicalDetails(profile)) ...[
            SizedBox(height: 8.r),
            _systemInfoSection(
              icon: Icons.developer_board_rounded,
              title: AppLocale.systemTechnicalDetails.getString(context),
              child: Wrap(
                spacing: 6.r,
                runSpacing: 6.r,
                children: [
                  if (profile?.generation != null)
                    _systemInfoDetailChip(
                      icon: Icons.history_rounded,
                      label: AppLocale.systemGeneration.getString(context),
                      value: profile!.generation.toString(),
                    ),
                  if ((profile?.cpu ?? '').trim().isNotEmpty)
                    _systemInfoDetailChip(
                      icon: Icons.memory_rounded,
                      label: AppLocale.systemProcessor.getString(context),
                      value: profile!.cpu!.trim(),
                    ),
                  if (profile?.media.isNotEmpty ?? false)
                    _systemInfoDetailChip(
                      icon: Icons.album_rounded,
                      label: AppLocale.systemMedia.getString(context),
                      value: profile!.media
                          .map(_localizedMedia)
                          .where((e) => e.isNotEmpty)
                          .join(' • '),
                    ),
                  _systemInfoDetailChip(
                    icon: Icons.sports_esports_rounded,
                    label: AppLocale.systemGamesDetected.getString(context),
                    value: _system.romCount.toString(),
                  ),
                ],
              ),
            ),
          ],

          if (profile?.notableGames.isNotEmpty ?? false) ...[
            SizedBox(height: 8.r),
            _systemInfoSection(
              icon: Icons.star_rounded,
              title: AppLocale.systemNotableGames.getString(context),
              child: Wrap(
                spacing: 5.r,
                runSpacing: 5.r,
                children: profile!.notableGames
                    .map((title) => _systemInfoTextChip(title))
                    .toList(),
              ),
            ),
          ],

          if (_system.extensions.isNotEmpty) ...[
            SizedBox(height: 8.r),
            _systemInfoSection(
              icon: Icons.insert_drive_file_rounded,
              title: AppLocale.supportedFormats.getString(context),
              child: Wrap(
                spacing: 5.r,
                runSpacing: 5.r,
                children: _system.extensions
                    .map((ext) => _systemInfoTextChip(ext.toUpperCase()))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _systemInfoIdentity(ThemeData theme, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 9.r),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius:
            theme.extension<CornerRadii>()?.radiusInternal ??
            BorderRadius.circular(10.r),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.18),
          width: 1.r,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              _systemTypeIcon(_system.type),
              size: 23.r,
              color: scheme.primary,
            ),
          ),
          SizedBox(width: 10.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _system.realName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5.r,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if ((_system.shortName ?? '').trim().isNotEmpty) ...[
                  SizedBox(height: 1.r),
                  Text(
                    _system.shortName!.trim(),
                    style: TextStyle(
                      fontSize: 8.5.r,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildDetailedSummary({
    required SystemInfoProfile? profile,
    required String typeLabel,
    required String manufacturer,
    required bool hasManufacturer,
    required String year,
  }) {
    final parts = <String>[];
    final introKey = hasManufacturer
        ? AppLocale.systemInfoDetailedIntro
        : AppLocale.systemInfoDetailedIntroNoManufacturer;
    parts.add(
      introKey
          .getString(context)
          .replaceAll('{name}', _system.realName)
          .replaceAll('{type}', typeLabel)
          .replaceAll('{manufacturer}', manufacturer)
          .replaceAll('{year}', year),
    );

    final architecture = (profile?.architecture ?? '').trim();
    if (architecture.isNotEmpty) {
      parts.add(
        AppLocale.systemInfoArchitectureSentence
            .getString(context)
            .replaceAll('{architecture}', architecture),
      );
    }
    if (profile?.generation != null) {
      parts.add(
        AppLocale.systemInfoGenerationSentence
            .getString(context)
            .replaceAll('{generation}', profile!.generation.toString()),
      );
    }
    final cpu = (profile?.cpu ?? '').trim();
    if (cpu.isNotEmpty) {
      parts.add(
        AppLocale.systemInfoProcessorSentence
            .getString(context)
            .replaceAll('{cpu}', cpu),
      );
    }
    if (profile?.media.isNotEmpty ?? false) {
      final media = profile!.media.map(_localizedMedia).join(', ');
      parts.add(
        AppLocale.systemInfoMediaSentence
            .getString(context)
            .replaceAll('{media}', media),
      );
    }

    final collectionNote = _localizedCollectionNote(profile?.collectionKind);
    if (collectionNote.isNotEmpty) parts.add(collectionNote);

    return parts.join(' ');
  }

  bool _hasTechnicalDetails(SystemInfoProfile? profile) {
    return profile?.generation != null ||
        (profile?.cpu ?? '').trim().isNotEmpty ||
        (profile?.media.isNotEmpty ?? false) ||
        _system.romCount >= 0;
  }

  String get _systemYear {
    final raw = (_system.launchDate ?? '').trim();
    if (raw.length >= 4) {
      final firstFour = raw.substring(0, 4);
      if (int.tryParse(firstFour) != null) return firstFour;
    }
    return AppLocale.unknown.getString(context);
  }

  String _localizedSystemType(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'console':
        return AppLocale.systemTypeConsole.getString(context);
      case 'handheld':
        return AppLocale.systemTypeHandheld.getString(context);
      case 'computer':
        return AppLocale.systemTypeComputer.getString(context);
      case 'arcade':
        return AppLocale.systemTypeArcade.getString(context);
      case 'virtual':
        return AppLocale.systemTypeVirtual.getString(context);
      default:
        return AppLocale.unknown.getString(context);
    }
  }

  String _localizedMedia(String code) {
    final key = switch (code) {
      'cartridge' => AppLocale.mediaCartridge,
      'cd_rom' => AppLocale.mediaCdRom,
      'dvd' => AppLocale.mediaDvd,
      'blu_ray' => AppLocale.mediaBluRay,
      'floppy' => AppLocale.mediaFloppy,
      'cassette' => AppLocale.mediaCassette,
      'digital' => AppLocale.mediaDigital,
      'arcade_board' => AppLocale.mediaArcadeBoard,
      'optical_disc' => AppLocale.mediaOpticalDisc,
      'umd' => AppLocale.mediaUmd,
      'gd_rom' => AppLocale.mediaGdRom,
      'hucard' => AppLocale.mediaHuCard,
      'built_in' => AppLocale.mediaBuiltIn,
      'broadcast' => AppLocale.mediaBroadcast,
      'hard_disk' => AppLocale.mediaHardDisk,
      'card' => AppLocale.mediaCard,
      'various' => AppLocale.mediaVarious,
      _ => '',
    };
    return key.isEmpty ? code : key.getString(context);
  }

  String _localizedCollectionNote(String? kind) {
    final key = switch (kind) {
      'rom_hacks' => AppLocale.systemInfoCollectionRomHacks,
      'all_systems' => AppLocale.systemInfoCollectionAllSystems,
      'favorites' => AppLocale.systemInfoCollectionFavorites,
      'digital_store' => AppLocale.systemInfoCollectionDigitalStore,
      'emulation_platform' => AppLocale.systemInfoCollectionEmulationPlatform,
      'fantasy_console' => AppLocale.systemInfoCollectionFantasyConsole,
      'media_collection' => AppLocale.systemInfoCollectionMediaCollection,
      'game_engine' => AppLocale.systemInfoCollectionGameEngine,
      'software_platform' => AppLocale.systemInfoCollectionSoftwarePlatform,
      _ => '',
    };
    return key.isEmpty ? '' : key.getString(context);
  }

  IconData _systemTypeIcon(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'handheld':
        return Icons.smartphone_rounded;
      case 'computer':
        return Icons.computer_rounded;
      case 'arcade':
        return Icons.sports_esports_rounded;
      case 'virtual':
        return Icons.folder_special_rounded;
      case 'console':
      default:
        return Icons.videogame_asset_rounded;
    }
  }

  Widget _systemInfoMetric({
    required double width,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.5.r),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.10),
          width: 1.r,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13.r, color: scheme.primary),
          SizedBox(width: 5.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 7.r,
                    color: scheme.onSurface.withValues(alpha: 0.50),
                  ),
                ),
                SizedBox(height: 1.r),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 8.5.r,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemInfoDetailChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxWidth: 300.r),
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 5.r),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.12),
          width: 1.r,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.r, color: scheme.primary),
          SizedBox(width: 4.r),
          Flexible(
            child: Text(
              '$label: $value',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8.r,
                height: 1.2,
                color: scheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemInfoTextChip(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.r, vertical: 3.r),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7.8.r,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface.withValues(alpha: 0.74),
        ),
      ),
    );
  }

  Widget _systemInfoSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(9.r),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.035),
        borderRadius:
            theme.extension<CornerRadii>()?.radiusInternal ??
            BorderRadius.circular(10.r),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.09),
          width: 1.r,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12.r, color: scheme.primary),
              SizedBox(width: 5.r),
              Text(
                title,
                style: TextStyle(
                  fontSize: 8.7.r,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: 5.r),
          child,
        ],
      ),
    );
  }
}

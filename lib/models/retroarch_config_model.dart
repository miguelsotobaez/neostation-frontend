/// Represents the configuration and directory structure for a RetroArch installation.
///
/// Stores paths for critical RetroArch directories such as system (BIOS),
/// save files, and save states.
class RetroArchConfig {
  /// Unique identifier for the configuration entry in the local database.
  final int? id;

  /// Absolute filesystem path to the `retroarch.cfg` configuration file.
  final String configPath;

  /// Directory used for system-specific files such as BIOS and firmware.
  final String? systemDirectory;

  /// Directory where game save data (SRAM, Battery) is stored.
  final String? savefileDirectory;

  /// Directory where save state snapshots are stored.
  final String? savestateDirectory;

  /// Whether RetroArch files save data into a per-core subfolder
  /// (`sort_savefiles_enable`). When true a `.srm` lands in
  /// `<savefileDirectory>/<Core Name>/` rather than the directory root.
  final bool sortSavefilesByCore;

  /// Whether RetroArch files save states into a per-core subfolder
  /// (`sort_savestates_enable`). Tracked separately from
  /// [sortSavefilesByCore] because RetroArch exposes the two as independent
  /// settings and users do enable just one.
  final bool sortSavestatesByCore;

  const RetroArchConfig({
    this.id,
    required this.configPath,
    this.systemDirectory,
    this.savefileDirectory,
    this.savestateDirectory,
    this.sortSavefilesByCore = false,
    this.sortSavestatesByCore = false,
  });

  /// Creates a [RetroArchConfig] instance from a JSON-compatible map.
  factory RetroArchConfig.fromJson(Map<String, dynamic> json) {
    return RetroArchConfig(
      id: int.tryParse((json['id'] ?? '').toString()),
      configPath: (json['config_path'] ?? json['configPath'] ?? '').toString(),
      systemDirectory: (json['system_directory'] ?? json['systemDirectory'])
          ?.toString(),
      savefileDirectory:
          (json['savefile_directory'] ?? json['savefileDirectory'])?.toString(),
      savestateDirectory:
          (json['savestate_directory'] ?? json['savestateDirectory'])
              ?.toString(),
      sortSavefilesByCore:
          json['sort_savefiles_by_core'] == true ||
          json['sortSavefilesByCore'] == true,
      sortSavestatesByCore:
          json['sort_savestates_by_core'] == true ||
          json['sortSavestatesByCore'] == true,
    );
  }

  /// Converts the configuration instance into a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'config_path': configPath,
      'system_directory': systemDirectory,
      'savefile_directory': savefileDirectory,
      'savestate_directory': savestateDirectory,
      'sort_savefiles_by_core': sortSavefilesByCore,
      'sort_savestates_by_core': sortSavestatesByCore,
    };
  }

  /// Returns a copy of the configuration with the specified fields updated.
  RetroArchConfig copyWith({
    int? id,
    String? configPath,
    String? systemDirectory,
    String? savefileDirectory,
    String? savestateDirectory,
    bool? sortSavefilesByCore,
    bool? sortSavestatesByCore,
  }) {
    return RetroArchConfig(
      id: id ?? this.id,
      configPath: configPath ?? this.configPath,
      systemDirectory: systemDirectory ?? this.systemDirectory,
      savefileDirectory: savefileDirectory ?? this.savefileDirectory,
      savestateDirectory: savestateDirectory ?? this.savestateDirectory,
      sortSavefilesByCore: sortSavefilesByCore ?? this.sortSavefilesByCore,
      sortSavestatesByCore: sortSavestatesByCore ?? this.sortSavestatesByCore,
    );
  }

  @override
  String toString() {
    return 'RetroArchConfig(id: $id, path: $configPath, system: $systemDirectory, saves: $savefileDirectory, states: $savestateDirectory)';
  }
}

import 'system_model.dart';

/// Represents a standardized definition for an emulator available for a system.
///
/// Contains metadata about the emulator's capabilities, its compatibility
/// across different platforms (OS), and whether it supports RetroAchievements.
class EmulatorDefinition {
  /// User-friendly name of the emulator (e.g., 'RetroArch (Snes9x)').
  final String name;

  /// A stable, unique identifier string (e.g., 'snes.ra.snes9x').
  final String uniqueId;

  /// Short summary or technical notes about the emulator's performance or features.
  final String description;

  /// Map containing platform-specific execution details (e.g., 'android', 'windows').
  final Map<String, dynamic> platforms;

  /// Whether this RetroArch core is the recommended default core for the system.
  final bool isDefaultCore;

  /// Whether this standalone emulator is the recommended default for the system.
  final bool isDefaultStandalone;

  /// Whether the emulator supports RetroAchievements synchronization.
  final bool? isretroAchievementsCompatible;

  const EmulatorDefinition({
    required this.name,
    required this.uniqueId,
    required this.description,
    required this.platforms,
    this.isDefaultCore = false,
    this.isDefaultStandalone = false,
    this.isretroAchievementsCompatible,
  });

  /// Creates an [EmulatorDefinition] from a JSON-compatible map.
  factory EmulatorDefinition.fromJson(Map<String, dynamic> json) {
    return EmulatorDefinition(
      name: (json['name'] ?? '').toString(),
      uniqueId: (json['unique_id'] ?? json['uniqueId'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      platforms: json['platforms'] is Map
          ? Map<String, dynamic>.from(json['platforms'])
          : {},
      isDefaultCore:
          (json['default_core'] ?? false).toString().toLowerCase() == 'true',
      isDefaultStandalone:
          (json['default_standalone'] ?? false).toString().toLowerCase() ==
          'true',
      isretroAchievementsCompatible:
          (json['is_retroachievements_compatible'] ??
                      json['is_ra_compatible'] ??
                      false)
                  .toString()
                  .toLowerCase() ==
              'true' ||
          (json['is_retroachievements_compatible'] ??
                      json['is_ra_compatible'] ??
                      0)
                  .toString() ==
              '1',
    );
  }
}

/// Combines a [SystemModel] with its available [EmulatorDefinition]s.
///
/// This aggregate model is typically used when configuring a system's
/// scanning and playback options within the UI.
class SystemConfiguration {
  /// The underlying system metadata.
  final SystemModel system;

  /// List of emulators capable of launching ROMs for this system.
  final List<EmulatorDefinition> emulators;

  const SystemConfiguration({required this.system, required this.emulators});
}

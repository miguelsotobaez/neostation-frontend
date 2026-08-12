/// Represents an emulator or libretro core entry from the `app_emulators` table.
class CoreEmulatorModel {
  /// Unique identifier for the emulator/core configuration.
  final String uniqueId;

  /// OS identifier (e.g., 1 for Windows, 2 for Android).
  final int osId;

  /// Identifier of the system this emulator supports (e.g., 'nes', 'psx').
  final String systemId;

  /// Human-readable name of the emulator.
  final String name;

  /// Indicates if this is a standalone executable or a libretro core.
  final bool isStandalone;

  /// Filename of the libretro core (e.g., 'snes9x_libretro.so'), if applicable.
  final String? coreFilename;

  /// Whether this emulator is the default choice for its system.
  final bool isDefault;

  /// Whether this core is marked as default_core in the system definition JSON.
  final bool isDefaultCore;

  /// Whether this emulator supports RetroAchievements.
  final bool isretroAchievementsCompatible;

  /// Android package name for intent-based launching (e.g., 'com.retroarch'), if applicable.
  final String? androidPackageName;

  /// iOS URL scheme used to detect/open the emulator, if applicable.
  final String? iosUrlScheme;

  /// Whether the emulator is actually present and usable on this device.
  ///
  /// Only a verifying enumerator sets this: `loadEmulatorsForSystem` checks the
  /// Android package *and* the libretro core file, or probes the desktop cores
  /// directory. A model built straight from a database row leaves it `false` —
  /// the row alone cannot answer the question. If you need a trustworthy
  /// answer, go through `loadEmulatorsForSystem`, not a raw query.
  final bool isInstalled;

  /// Whether a desktop executable path is configured for this emulator.
  ///
  /// Desktop-only signal, read from `user_emulator_config.emulator_path`.
  /// Nothing populates that column on Android, so it is always `false` there —
  /// it is *not* an install check, and was previously aliased as one
  /// (`is_installed`), which made every Android emulator look uninstalled.
  final bool hasConfiguredPath;

  /// Whether this emulator is a RetroArch variant (e.g. `com.retroarch`,
  /// `com.retroarch.aarch64`). RetroArch variants all share the same launch
  /// activity, so only their package differs — which is why substituting one
  /// variant's package into a RetroArch intent is safe, while substituting a
  /// standalone emulator's package is not.
  bool get isRetroArch =>
      androidPackageName != null &&
      androidPackageName!.startsWith(CoreEmulatorModel.retroArchPackagePrefix);

  /// Package prefix shared by every RetroArch variant.
  static const String retroArchPackagePrefix = 'com.retroarch';

  /// Every RetroArch variant, best first.
  ///
  /// "Best" means most capable on the widest range of current devices, so an
  /// arm64 build outranks the legacy universal one, which outranks the 32-bit
  /// build. Callers that must choose between several *installed* variants
  /// should follow this order rather than whatever order the database returns.
  static const List<String> retroArchPackagePriority = [
    'com.retroarch.aarch64',
    'com.retroarch',
    'com.retroarch.ra32',
  ];

  const CoreEmulatorModel({
    required this.uniqueId,
    required this.osId,
    required this.systemId,
    required this.name,
    required this.isStandalone,
    this.coreFilename,
    required this.isDefault,
    this.isDefaultCore = false,
    required this.isretroAchievementsCompatible,
    this.androidPackageName,
    this.iosUrlScheme,
    this.isInstalled = false,
    this.hasConfiguredPath = false,
  });

  /// Creates a [CoreEmulatorModel] from a database row map.
  factory CoreEmulatorModel.fromMap(Map<String, dynamic> map) {
    return CoreEmulatorModel(
      uniqueId: map['unique_identifier'].toString(),
      osId: int.tryParse(map['os_id']?.toString() ?? '0') ?? 0,
      systemId: map['system_id'].toString(),
      name: map['name'].toString(),
      isStandalone:
          (int.tryParse(map['is_standalone']?.toString() ?? '0') ?? 0) == 1,
      coreFilename: map['core_filename']?.toString(),
      isDefault: (int.tryParse(map['is_default']?.toString() ?? '0') ?? 0) == 1,
      isDefaultCore:
          (int.tryParse(map['is_default_core']?.toString() ?? '0') ?? 0) == 1,
      isretroAchievementsCompatible:
          (int.tryParse(map['is_ra_compatible']?.toString() ?? '0') ?? 0) == 1,
      androidPackageName: map['android_package_name']?.toString(),
      iosUrlScheme: map['ios_url_scheme']?.toString(),
      isInstalled: (map['is_installed'] == 1 || map['is_installed'] == true),
      hasConfiguredPath:
          (map['has_configured_path'] == 1 ||
          map['has_configured_path'] == true),
    );
  }

  /// Converts the model instance into a map for database operations.
  Map<String, dynamic> toMap() {
    return {
      'unique_identifier': uniqueId,
      'os_id': osId,
      'system_id': systemId,
      'name': name,
      'is_standalone': isStandalone ? 1 : 0,
      'core_filename': coreFilename,
      'is_default': isDefault ? 1 : 0,
      'is_default_core': isDefaultCore ? 1 : 0,
      'is_ra_compatible': isretroAchievementsCompatible ? 1 : 0,
      'android_package_name': androidPackageName,
      'ios_url_scheme': iosUrlScheme,
    };
  }

  /// Returns a new instance with updated properties.
  CoreEmulatorModel copyWith({
    String? uniqueId,
    int? osId,
    String? systemId,
    String? name,
    bool? isStandalone,
    String? coreFilename,
    bool? isDefault,
    bool? isDefaultCore,
    bool? isretroAchievementsCompatible,
    String? androidPackageName,
    String? iosUrlScheme,
    bool? isInstalled,
    bool? hasConfiguredPath,
  }) {
    return CoreEmulatorModel(
      uniqueId: uniqueId ?? this.uniqueId,
      osId: osId ?? this.osId,
      systemId: systemId ?? this.systemId,
      name: name ?? this.name,
      isStandalone: isStandalone ?? this.isStandalone,
      coreFilename: coreFilename ?? this.coreFilename,
      isDefault: isDefault ?? this.isDefault,
      isDefaultCore: isDefaultCore ?? this.isDefaultCore,
      isretroAchievementsCompatible:
          isretroAchievementsCompatible ?? this.isretroAchievementsCompatible,
      androidPackageName: androidPackageName ?? this.androidPackageName,
      iosUrlScheme: iosUrlScheme ?? this.iosUrlScheme,
      isInstalled: isInstalled ?? this.isInstalled,
      hasConfiguredPath: hasConfiguredPath ?? this.hasConfiguredPath,
    );
  }

  @override
  String toString() {
    return 'CoreEmulatorModel(uniqueId: $uniqueId, name: $name, isDefault: $isDefault, isDefaultCore: $isDefaultCore, isretroAchievementsCompatible: $isretroAchievementsCompatible, androidPackageName: $androidPackageName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoreEmulatorModel &&
        other.uniqueId == uniqueId &&
        other.osId == osId;
  }

  @override
  int get hashCode => Object.hash(uniqueId, osId);

  /// Accessor for dynamic key-based property retrieval.
  dynamic operator [](String key) {
    switch (key) {
      case 'unique_identifier':
      case 'uniqueId':
        return uniqueId;
      case 'os_id':
        return osId;
      case 'system_id':
        return systemId;
      case 'name':
        return name;
      case 'is_standalone':
        return isStandalone ? 1 : 0;
      case 'core_filename':
        return coreFilename;
      case 'is_default':
        return isDefault ? 1 : 0;
      case 'is_default_core':
        return isDefaultCore ? 1 : 0;
      case 'is_ra_compatible':
        return isretroAchievementsCompatible ? 1 : 0;
      case 'android_package_name':
        return androidPackageName;
      case 'ios_url_scheme':
        return iosUrlScheme;
      case 'is_installed':
        return isInstalled;
      case 'has_configured_path':
        return hasConfiguredPath;
      default:
        return null;
    }
  }
}

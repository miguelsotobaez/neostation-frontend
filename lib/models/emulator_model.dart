import 'dart:io';

import '../services/macos_application_service.dart';

/// Represents an emulator installation or a target application for launching ROMs.
class EmulatorModel {
  /// The human-readable name of the emulator (e.g., 'RetroArch', 'DuckStation').
  final String name;

  /// The absolute filesystem path to the executable or the Android package name.
  final String path;

  /// Whether the application has been successfully located on the current system.
  final bool detected;

  /// Timestamp of the last successful automatic detection.
  final DateTime? lastDetection;

  /// Map of potential executable paths, categorized by operating system ('windows', 'linux', etc.).
  final Map<String, List<String>> possiblePaths;

  /// Unique identifier referencing an entry in the `app_emulators` table.
  final String? uniqueId;

  const EmulatorModel({
    required this.name,
    required this.path,
    required this.detected,
    this.lastDetection,
    this.possiblePaths = const {},
    this.uniqueId,
  });

  /// Creates an [EmulatorModel] from a JSON-compatible map.
  factory EmulatorModel.fromJson(String name, Map<String, dynamic> json) {
    return EmulatorModel(
      name: name,
      path: json['path']?.toString() ?? '',
      detected:
          (json['detected'] ?? false).toString().toLowerCase() == 'true' ||
          (json['detected'] ?? 0).toString() == '1',
      lastDetection: json['lastDetection'] != null
          ? DateTime.tryParse(json['lastDetection'].toString())
          : null,
      possiblePaths: json['possiblePaths'] != null
          ? Map<String, List<String>>.from(
              (json['possiblePaths'] as Map).map(
                (key, value) => MapEntry(
                  key.toString(),
                  List<String>.from((value as List).map((e) => e.toString())),
                ),
              ),
            )
          : {},
      uniqueId: json['uniqueId']?.toString(),
    );
  }

  /// Converts the emulator model into a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'detected': detected,
      'lastDetection': lastDetection?.toIso8601String(),
      if (possiblePaths.isNotEmpty) 'possiblePaths': possiblePaths,
      if (uniqueId != null) 'uniqueId': uniqueId,
    };
  }

  /// Attempts to locate the emulator executable on the current filesystem based on [possiblePaths].
  ///
  /// For Android, this typically stores the package name. For desktop platforms,
  /// it verifies file existence.
  Future<EmulatorModel> detect() async {
    final platform = Platform.operatingSystem;
    final paths = possiblePaths[platform] ?? [];

    for (final testPath in paths) {
      if (platform == 'android') {
        // On Android, existence is managed by the native layer; we assume valid if the path is set.
        if (testPath.isNotEmpty) {
          return copyWith(
            path: testPath,
            detected: true,
            lastDetection: DateTime.now(),
          );
        }
      } else {
        // Desktop platforms: verify physical file existence.
        final file = File(testPath);
        if (await file.exists()) {
          return copyWith(
            path: testPath,
            detected: true,
            lastDetection: DateTime.now(),
          );
        }
      }
    }

    if (platform == 'macos') {
      final executable = await MacOsApplicationService.findInstalledApplication(
        applicationNames: [name],
        bundleIdentifierHint: uniqueId,
      );
      if (executable != null) {
        return copyWith(
          path: executable,
          detected: true,
          lastDetection: DateTime.now(),
        );
      }
    }

    return copyWith(detected: false);
  }

  /// Returns the list of potential paths for the currently active operating system.
  List<String> get currentPlatformPaths {
    final platform = Platform.operatingSystem;
    return possiblePaths[platform] ?? [];
  }

  /// Indicates if the emulator is detected and the specified path physically exists.
  bool get isAvailable =>
      detected && path.isNotEmpty && File(path).existsSync();

  /// Returns a new instance with the specified properties updated.
  EmulatorModel copyWith({
    String? name,
    String? path,
    bool? detected,
    DateTime? lastDetection,
    Map<String, List<String>>? possiblePaths,
    String? uniqueId,
  }) {
    return EmulatorModel(
      name: name ?? this.name,
      path: path ?? this.path,
      detected: detected ?? this.detected,
      lastDetection: lastDetection ?? this.lastDetection,
      possiblePaths: possiblePaths ?? this.possiblePaths,
      uniqueId: uniqueId ?? this.uniqueId,
    );
  }

  @override
  String toString() {
    return 'EmulatorModel(name: $name, path: $path, detected: $detected)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmulatorModel && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}

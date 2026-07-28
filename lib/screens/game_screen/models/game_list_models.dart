import 'package:neostation/services/logger_service.dart';

/// Transfer object for background game save detection tasks.
class GameSaveDetectionData {
  final String gameRomname;
  final String systemFolderName;

  GameSaveDetectionData({
    required this.gameRomname,
    required this.systemFolderName,
  });

  Map<String, dynamic> toJson() => {
    'gameRomname': gameRomname,
    'systemFolderName': systemFolderName,
  };

  factory GameSaveDetectionData.fromJson(Map<String, dynamic> json) =>
      GameSaveDetectionData(
        gameRomname: (json['gameRomname'] ?? '').toString(),
        systemFolderName: (json['systemFolderName'] ?? '').toString(),
      );
}

/// Dispatches a background isolate task to detect game saves without blocking the UI thread.
Future<void> detectGameSavesInBackground(GameSaveDetectionData data) async {
  try {
    // Current implementation placeholder for future isolate offloading.
    // Real-time detection logic resides in [_performBackgroundOperationsForSelectedGame].
    await Future.delayed(const Duration(milliseconds: 50));
  } catch (e) {
    LoggerService.instance.e('Background save detection failed: $e');
  }
}

/// Metadata container for localized description retrieval tasks.
class LocalizedDescriptionData {
  final String gameName;
  final String? preferredLanguage;

  LocalizedDescriptionData({required this.gameName, this.preferredLanguage});

  Map<String, dynamic> toJson() => {
    'gameName': gameName,
    'preferredLanguage': preferredLanguage,
  };

  factory LocalizedDescriptionData.fromJson(Map<String, dynamic> json) =>
      LocalizedDescriptionData(
        gameName: (json['gameName'] ?? '').toString(),
        preferredLanguage: json['preferredLanguage']?.toString(),
      );
}

/// Offloads localized description processing to a background task.
Future<String?> loadLocalizedDescriptionInBackground(
  LocalizedDescriptionData data,
) async {
  try {
    // Implementation placeholder for ScreenScraperService integration in isolates.
    await Future.delayed(const Duration(milliseconds: 50));
    return 'Description for ${data.gameName} in ${data.preferredLanguage ?? 'default'} language';
  } catch (e) {
    LoggerService.instance.e('Background description loading failed: $e');
    return null;
  }
}

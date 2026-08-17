import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/systems_update_service.dart';
import 'package:path/path.dart' as p;
import '../models/system_model.dart';
import '../models/system_configuration.dart';

/// Service responsible for loading and parsing system configuration JSON files.
///
/// Prefers locally cached files downloaded via [SystemsUpdateService] over
/// the bundled assets, and merges any new systems introduced by updates.
class JsonConfigService {
  static final JsonConfigService _instance = JsonConfigService._internal();
  static JsonConfigService get instance => _instance;
  JsonConfigService._internal();

  static final _log = LoggerService.instance;

  /// Loads all system configurations, preferring cached (updated) versions
  /// over bundled assets. Also picks up new systems added by remote updates.
  Future<List<SystemConfiguration>> loadSystems() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

      final bundledFiles = manifest
          .listAssets()
          .where(
            (key) => key.startsWith('assets/systems/') && key.endsWith('.json'),
          )
          .toList();

      final bundledFileNames = bundledFiles.map((f) => p.basename(f)).toSet();

      // Discover extra files in the cache not present in the bundle.
      final cachedOnlyFileNames = <String>{};
      try {
        final cacheDir = Directory(await SystemsUpdateService.getCacheDir());
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list()) {
            if (entity is File && entity.path.endsWith('.json')) {
              final name = p.basename(entity.path);
              if (!bundledFileNames.contains(name)) {
                cachedOnlyFileNames.add(name);
              }
            }
          }
        }
      } catch (e) {
        _log.w('JsonConfigService: error scanning cache dir: $e');
      }

      final allFileNames = {...bundledFileNames, ...cachedOnlyFileNames};
      final List<SystemConfiguration> systems = [];

      for (final fileName in allFileNames) {
        try {
          final String content;
          final cachedPath = await SystemsUpdateService.getCachedSystemPath(
            fileName,
          );
          if (cachedPath != null) {
            content = await File(cachedPath).readAsString();
          } else {
            content = await rootBundle.loadString('assets/systems/$fileName');
          }

          final Map<String, dynamic> jsonMap = json.decode(content);

          if (jsonMap.containsKey('system')) {
            final systemData = jsonMap['system'];

            // A definition downloaded before the RetroAchievements hashing
            // policy existed declares none, and a missing policy reads as the
            // permissive default — which would quietly cost NES, SNES and
            // arcade their algorithms for anyone who had ever taken a systems
            // update. The bundled copy of the same system still knows how it
            // must be hashed, so read that one field from it rather than
            // publishing a manifest bump to invalidate every user's cache.
            final raHash =
                systemData['ra_hash'] ??
                (cachedPath != null && bundledFileNames.contains(fileName)
                    ? await bundledRaHash(fileName)
                    : null);

            final flatMap = <String, dynamic>{
              'id': _generateId(systemData['id']),
              'folderName': systemData['id'],
              'realName': systemData['name'],
              'shortName': systemData['short_name'],
              'launchDate': systemData['details']?['release_date'],
              'description': systemData['details']?['description'],
              'manufacturer': systemData['details']?['manufacturer'],
              'type': systemData['details']?['type'],
              'screenscraperId': systemData['ids']?['screenscraper'],
              'raId': systemData['ids']?['retroachievements'],
              'raHashAlgo': raHash?['algo'],
              'raHashMode': raHash?['mode'],
              'iconImage': 'assets/images/systems/${systemData['id']}-icon.png',
              'backgroundImage':
                  'assets/images/systems/${systemData['id']}-bg.jpg',
              'color1':
                  (systemData['colors'] is List &&
                      (systemData['colors'] as List).isNotEmpty)
                  ? systemData['colors'][0].toString()
                  : null,
              'color2':
                  (systemData['colors'] is List &&
                      (systemData['colors'] as List).length > 1)
                  ? systemData['colors'][1].toString()
                  : null,
              'extensions': systemData['extensions'] ?? [],
              'folders': systemData['folders'] ?? [],
              'multidisc': systemData['multidisc'] ?? false,
              'neosync': jsonMap['neosync'],
            };

            final systemModel = SystemModel.fromJson(flatMap);

            List<EmulatorDefinition> emulators = [];
            final emulatorsKey = jsonMap.containsKey('emulators')
                ? 'emulators'
                : (jsonMap.containsKey('players') ? 'players' : null);

            if (emulatorsKey != null) {
              final playersList = jsonMap[emulatorsKey] as List;
              emulators = playersList
                  .map((e) => EmulatorDefinition.fromJson(e))
                  .toList();
            }

            systems.add(
              SystemConfiguration(system: systemModel, emulators: emulators),
            );
          }
        } catch (e) {
          _log.e('Error parsing system JSON $fileName: $e');
        }
      }

      return systems;
    } catch (e) {
      _log.e('Error loading system configurations: $e');
      return [];
    }
  }

  /// Reads just the `ra_hash` block from the *bundled* copy of [fileName].
  ///
  /// Used when a cached definition predates the hashing policy. Returns null if
  /// the bundled copy has none either, in which case the system genuinely
  /// declares no policy and gets the permissive default.
  @visibleForTesting
  Future<Map<String, dynamic>?> bundledRaHash(String fileName) async {
    try {
      final content = await rootBundle.loadString('assets/systems/$fileName');
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      final raHash = (jsonMap['system'] as Map?)?['ra_hash'];
      return raHash is Map<String, dynamic> ? raHash : null;
    } catch (e) {
      _log.w('Could not read bundled ra_hash for $fileName: $e');
      return null;
    }
  }

  int _generateId(String id) => id.hashCode;
}

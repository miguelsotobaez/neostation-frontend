import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'systems_update_service.dart';

/// Structured historical/technical metadata used by the System Info tab.
///
/// Rich information lives inside each `assets/systems/*.json` definition under
/// `system.details`. That keeps the feature aligned with NeoStation's existing
/// over-the-air system-definition updater instead of maintaining a second,
/// disconnected metadata database.
class SystemInfoProfile {
  final String? architecture;
  final int? generation;
  final String? cpu;
  final List<String> media;
  final List<String> notableGames;
  final String? collectionKind;

  const SystemInfoProfile({
    this.architecture,
    this.generation,
    this.cpu,
    this.media = const [],
    this.notableGames = const [],
    this.collectionKind,
  });

  factory SystemInfoProfile.fromDetails(Map<String, dynamic> details) {
    return SystemInfoProfile(
      architecture: details['architecture']?.toString(),
      generation: details['generation'] is int
          ? details['generation'] as int
          : int.tryParse(details['generation']?.toString() ?? ''),
      cpu: details['cpu']?.toString(),
      media:
          (details['media'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      notableGames:
          (details['notable_games'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      collectionKind: details['collection_kind']?.toString(),
    );
  }

  bool get hasRichData =>
      (architecture?.trim().isNotEmpty ?? false) ||
      generation != null ||
      (cpu?.trim().isNotEmpty ?? false) ||
      media.isNotEmpty ||
      notableGames.isNotEmpty ||
      (collectionKind?.trim().isNotEmpty ?? false);

  SystemInfoProfile merge(SystemInfoProfile child) {
    return SystemInfoProfile(
      architecture: child.architecture ?? architecture,
      generation: child.generation ?? generation,
      cpu: child.cpu ?? cpu,
      media: child.media.isNotEmpty ? child.media : media,
      notableGames: child.notableGames.isNotEmpty
          ? child.notableGames
          : notableGames,
      collectionKind: child.collectionKind ?? collectionKind,
    );
  }
}

class SystemInfoCatalog {
  SystemInfoCatalog._();

  /// Every bundled filename currently matches its system ID except this legacy
  /// Genesis-hacks definition. Keeping the alias here avoids changing the
  /// system ID and therefore preserves existing user data/folder mappings.
  static const Map<String, String> _fileAliases = {
    'gen-hacks': 'genesis-hacks.json',
  };

  static final Map<String, Future<SystemInfoProfile?>> _profileCache = {};

  static Future<SystemInfoProfile?> profileFor(String systemId) {
    return _profileCache.putIfAbsent(
      systemId,
      () => _resolve(systemId, <String>{}),
    );
  }

  static Future<SystemInfoProfile?> _resolve(
    String id,
    Set<String> resolving,
  ) async {
    if (!resolving.add(id)) return null; // inheritance-cycle guard

    final definition = await _loadDefinition(id);
    if (definition == null) {
      resolving.remove(id);
      return null;
    }

    final system = definition['system'];
    if (system is! Map) {
      resolving.remove(id);
      return null;
    }
    final detailsRaw = system['details'];
    final details = detailsRaw is Map
        ? Map<String, dynamic>.from(detailsRaw)
        : <String, dynamic>{};

    final current = SystemInfoProfile.fromDetails(details);
    final parentId = details['info_inherits']?.toString();
    if (parentId == null || parentId.isEmpty) {
      resolving.remove(id);
      return current;
    }

    final parent = await _resolve(parentId, resolving);
    resolving.remove(id);
    return parent?.merge(current) ?? current;
  }

  static Future<Map<String, dynamic>?> _loadDefinition(String id) async {
    final fileName = _fileAliases[id] ?? '$id.json';

    // Prefer the OTA cache when it already contains rich metadata. During the
    // transition to this feature, an older cached definition may not have the
    // new fields yet; in that case fall back to the enriched bundled asset.
    final cachedPath = await SystemsUpdateService.getCachedSystemPath(fileName);
    if (cachedPath != null) {
      try {
        final cached = _decode(await File(cachedPath).readAsString());
        if (_definitionHasRichInfo(cached)) return cached;
      } catch (_) {
        // Fall through to the bundled definition.
      }
    }

    try {
      final raw = await rootBundle.loadString('assets/systems/$fileName');
      return _decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String raw) {
    final decoded = json.decode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static bool _definitionHasRichInfo(Map<String, dynamic>? root) {
    if (root == null) return false;
    final system = root['system'];
    if (system is! Map) return false;
    final detailsRaw = system['details'];
    if (detailsRaw is! Map) return false;
    final details = Map<String, dynamic>.from(detailsRaw);
    return SystemInfoProfile.fromDetails(details).hasRichData ||
        (details['info_inherits']?.toString().isNotEmpty ?? false);
  }
}

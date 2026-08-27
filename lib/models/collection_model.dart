import 'system_model.dart';

/// Represents a user-created game collection (e.g. "Mario Series", "Fighting Classics").
///
/// Collections allow users to group games across multiple emulation systems.
class CollectionModel {
  /// Unique identifier of the collection.
  final int id;

  /// Human-readable title of the collection.
  final String name;

  /// Optional icon asset or symbol identifier.
  final String? icon;

  /// Optional accent color hex string (e.g. '#FF5722').
  final String? color;

  /// Optional custom background wallpaper image path.
  final String? customBackgroundPath;

  /// Optional custom logo/wheel image path.
  final String? customLogoPath;

  /// Image cache-busting version counter.
  final int imageVersion;

  /// Total number of active ROMs in this collection.
  final int romCount;

  /// Up to 4 ROM paths used for cover preview artwork.
  final List<String> coverRomPaths;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last updated timestamp.
  final DateTime? updatedAt;

  const CollectionModel({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.customBackgroundPath,
    this.customLogoPath,
    this.imageVersion = 0,
    this.romCount = 0,
    this.coverRomPaths = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// Creates a [CollectionModel] from a database row map.
  factory CollectionModel.fromMap(Map<String, dynamic> map) {
    List<String> parseCoverRomPaths(dynamic raw) {
      if (raw == null) return const [];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      if (raw is String && raw.isNotEmpty) {
        return raw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return CollectionModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: (map['name'] ?? '').toString(),
      icon: map['icon']?.toString(),
      color: map['color']?.toString(),
      customBackgroundPath: map['custom_background_path']?.toString(),
      customLogoPath: map['custom_logo_path']?.toString(),
      imageVersion: (map['image_version'] as num?)?.toInt() ?? 0,
      romCount: (map['game_count'] ?? map['rom_count'] as num?)?.toInt() ?? 0,
      coverRomPaths: parseCoverRomPaths(
        map['cover_rom_paths'] ?? map['coverRomPaths'],
      ),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  /// Converts the collection to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id == 0 ? null : id,
      'name': name,
      'icon': icon ?? '',
      'color': color ?? '',
      'custom_background_path': customBackgroundPath ?? '',
      'custom_logo_path': customLogoPath ?? '',
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Returns a copy of the collection with updated fields.
  CollectionModel copyWith({
    int? id,
    String? name,
    String? icon,
    String? color,
    String? customBackgroundPath,
    String? customLogoPath,
    int? imageVersion,
    int? romCount,
    List<String>? coverRomPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CollectionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      customBackgroundPath: customBackgroundPath ?? this.customBackgroundPath,
      customLogoPath: customLogoPath ?? this.customLogoPath,
      imageVersion: imageVersion ?? this.imageVersion,
      romCount: romCount ?? this.romCount,
      coverRomPaths: coverRomPaths ?? this.coverRomPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this collection to a virtual [SystemModel] for browsing in [SystemGamesList].
  SystemModel toSystemModel() {
    final hasCustomLogo = customLogoPath != null && customLogoPath!.isNotEmpty;
    return SystemModel(
      id: 'collection_$id',
      folderName: 'collection_$id',
      realName: name,
      iconImage: hasCustomLogo
          ? customLogoPath!
          : (icon != null && icon!.isNotEmpty
                ? icon!
                : '/images/icons/folder-bulk.png'),
      customLogoPath: customLogoPath,
      customBackgroundPath: customBackgroundPath,
      imageVersion: imageVersion,
      color: color != null && color!.isNotEmpty ? color! : '#ff006a',
      romCount: romCount,
      isVirtual: true,
      detected: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          romCount == other.romCount &&
          customBackgroundPath == other.customBackgroundPath &&
          customLogoPath == other.customLogoPath &&
          imageVersion == other.imageVersion;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      romCount.hashCode ^
      (customBackgroundPath?.hashCode ?? 0) ^
      (customLogoPath?.hashCode ?? 0) ^
      imageVersion.hashCode;
}

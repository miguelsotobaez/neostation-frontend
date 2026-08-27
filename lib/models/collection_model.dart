import 'system_model.dart';

/// Represents a user-created game collection (e.g. "Mario Series", "Fighting Classics").
///
/// Collections allow users to group games across multiple emulation systems.
class CollectionModel {
  /// Unique identifier of the collection.
  final int id;

  /// Human-readable title of the collection.
  final String name;

  /// Optional description or subtitle.
  final String? description;

  /// Optional icon asset or symbol identifier.
  final String? icon;

  /// Optional accent color hex string (e.g. '#FF5722').
  final String? color;

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
    this.description,
    this.icon,
    this.color,
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
      description: map['description']?.toString(),
      icon: map['icon']?.toString(),
      color: map['color']?.toString(),
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
      'description': description ?? '',
      'icon': icon ?? '',
      'color': color ?? '',
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Returns a copy of the collection with updated fields.
  CollectionModel copyWith({
    int? id,
    String? name,
    String? description,
    String? icon,
    String? color,
    int? romCount,
    List<String>? coverRomPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CollectionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      romCount: romCount ?? this.romCount,
      coverRomPaths: coverRomPaths ?? this.coverRomPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this collection to a virtual [SystemModel] for browsing in [SystemGamesList].
  SystemModel toSystemModel() {
    return SystemModel(
      id: 'collection_$id',
      folderName: 'collection_$id',
      realName: name,
      description: description,
      iconImage: icon != null && icon!.isNotEmpty
          ? icon!
          : '/images/icons/folder-bulk.png',
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
          romCount == other.romCount;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ romCount.hashCode;
}

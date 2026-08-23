/// A platform (console/system) as exposed by a remote RomM server.
///
/// This describes the *remote* library and is deliberately kept separate from
/// [SystemModel], which represents a locally configured system.
class RommPlatform {
  /// RomM internal platform id (used in `?platform_id=` queries).
  final int id;

  /// Human-readable name (e.g. "Super Nintendo Entertainment System").
  final String name;

  /// RomM platform slug (e.g. "snes"), used to map to a local system folder.
  final String slug;

  /// Filesystem slug used by RomM on disk; a useful fallback for mapping.
  final String? fsSlug;

  /// Number of ROMs RomM reports for this platform.
  final int romCount;

  /// Logo image URL (typically a public IGDB CDN URL), or null.
  final String? urlLogo;

  const RommPlatform({
    required this.id,
    required this.name,
    required this.slug,
    this.fsSlug,
    this.romCount = 0,
    this.urlLogo,
  });

  factory RommPlatform.fromJson(Map<String, dynamic> json) {
    return RommPlatform(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? json['slug']?.toString() ?? 'Unknown',
      slug: json['slug']?.toString() ?? '',
      fsSlug: json['fs_slug']?.toString(),
      romCount: (json['rom_count'] as num?)?.toInt() ?? 0,
      urlLogo: json['url_logo']?.toString(),
    );
  }
}

import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';

/// Resolves the hardware system [game] actually belongs to.
///
/// In an aggregate view ('all', 'favorites', `collection:<uuid>`) the list's
/// own [listSystem] is a synthesized placeholder standing for the *view*, not
/// for any hardware: a collection's id has no `app_systems` row behind it at
/// all. Anything that needs a real system — enumerating emulators, scraper
/// ids, per-system settings — must therefore resolve against the selected
/// game's system, never the list's.
///
/// [detectedSystems] is the provider's detected-system list; its aggregate
/// entries are skipped so the answer can never be another placeholder.
///
/// Falls back to [listSystem] when the view is not an aggregate one, or when
/// the game's system cannot be found, which keeps every single-system view on
/// exactly the path it took before.
SystemModel resolveEffectiveSystem({
  required SystemModel listSystem,
  required GameModel game,
  required List<SystemModel> detectedSystems,
}) {
  if (!SystemFolderNames.isAggregate(listSystem.folderName)) return listSystem;

  final real = detectedSystems.where(
    (s) => !SystemFolderNames.isAggregate(s.folderName),
  );

  // Prefer the id: `DatabaseGameModel.fromJson` reads the `system_id` alias the
  // aggregate queries give `app_systems.id`, so it is populated here.
  final systemId = game.systemId;
  if (systemId != null && systemId.isNotEmpty) {
    for (final system in real) {
      if (system.id == systemId) return system;
    }
  }

  final folderName = game.systemFolderName;
  if (folderName == null || folderName.isEmpty) return listSystem;
  for (final system in real) {
    if (system.folderName == folderName) return system;
  }
  // ES-DE style aliases: the game row can carry one of the system's alternative
  // folder names rather than its primary one.
  for (final system in real) {
    if (system.folders.contains(folderName)) return system;
  }
  return listSystem;
}

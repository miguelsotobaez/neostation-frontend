class SystemFolderNames {
  static const String favorites = 'favorites';
  static const String all = 'all';
  static const String music = 'music';
  static const String android = 'android';

  /// Systems the "Recursive Scan" setting cannot apply to: they own no ROM
  /// folder to walk. [all] and [favorites] aggregate games that belong to other
  /// systems, and [android] lists installed apps.
  ///
  /// Offering the switch on one of these is not merely inert: flipping it
  /// triggers a real scan for a folder of that name, which would file whatever
  /// it found under a system that is supposed to hold nothing of its own.
  ///
  /// [music] is deliberately absent — it owns a real folder that can nest.
  ///
  /// A new virtual system belongs here the moment it is added to
  /// `assets/systems/`, together with a migration that clears both flags on
  /// databases that already carry a row for it.
  static const Set<String> recursiveScanExcluded = {all, favorites, android};

  /// Systems the subfolder view cannot apply to: everything in
  /// [recursiveScanExcluded], plus the music library, which owns a folder but
  /// is browsed as a playlist rather than a folder tree. The game list skips
  /// the setting for these, so the global "Show Subfolders" toggle leaves them
  /// alone rather than writing a flag nothing will ever read.
  ///
  /// This must stay a superset of [recursiveScanExcluded]: the per-system
  /// settings dialog stacks "Show Subfolders" directly under "Recursive Scan"
  /// and addresses both by position, so a system may never drop the recursive
  /// row while keeping the subfolder one.
  static const Set<String> subfolderViewExcluded = {
    ...recursiveScanExcluded,
    music,
  };
}

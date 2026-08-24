class SystemFolderNames {
  static const String favorites = 'favorites';
  static const String all = 'all';
  static const String music = 'music';
  static const String android = 'android';

  /// Systems the subfolder view cannot apply to: virtual aggregates that own no
  /// ROM folder of their own ([all], [favorites]), the music library, and the
  /// installed-apps grid. The game list skips the setting for these, so the
  /// global "Show Subfolders" toggle leaves them alone rather than writing a
  /// flag nothing will ever read.
  static const Set<String> subfolderViewExcluded = {
    all,
    favorites,
    music,
    android,
  };
}

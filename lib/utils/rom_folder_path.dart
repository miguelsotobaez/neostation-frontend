/// Classification of ROM-folder paths whose lifetime is shorter than the
/// configuration that stores them.
library;

/// The XDG document portal's FUSE mount, e.g.
/// `/run/user/1000/doc/d4efb740/roms`.
///
/// The desktop file-chooser portal hands a sandboxed client a path under this
/// mount instead of the real location. The `<handle>` segment is minted per
/// grant and the mount is torn down with the user session, so a path captured
/// from it is dead after a reboot: it resolves to an empty directory rather
/// than failing loudly, and a scan that trusts it finds no ROMs.
final RegExp _documentPortalPath = RegExp(r'^/run/user/\d+/doc(/|$)');

/// The same mount as seen from inside a Flatpak sandbox on some runtimes.
final RegExp _flatpakDocumentPath = RegExp(r'^/run/flatpak/doc(/|$)');

/// Whether [path] lives on a desktop-portal document mount and will therefore
/// stop resolving once the granting session ends.
///
/// Such a path must never be persisted as a ROM directory: the library it
/// describes silently empties on the next boot.
bool isTransientPortalPath(String path) {
  if (path.isEmpty) return false;
  return _documentPortalPath.hasMatch(path) ||
      _flatpakDocumentPath.hasMatch(path);
}

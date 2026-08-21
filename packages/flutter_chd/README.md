# flutter_chd

Reads tracks and sectors out of CHD disc images, so RetroAchievements hashing
can reach the executable inside a disc's filesystem.

Both CHD layouts a game library holds are read: a CD image, whose tracks are
listed in metadata and whose frames wrap their user data in sector headers, and
a DVD image, which has neither and is one flat run of 2048-byte sectors.

RetroAchievements identifies a disc game by hashing its primary executable, not
the container, so a plain MD5 of a `.chd` matches nothing in RA's database. This
plugin supplies the one thing that cannot be done in Dart — decompressing CHD
hunks — and stops there: the ISO9660 parsing and the per-console hashing live in
the app, where they are shared with `.iso` and `.cue`/`.bin` images that need no
native code at all.

## API

```dart
final disc = ChdDisc.open('/roms/psx/Game.chd');   // or ChdDisc.openFd(fd)
final track = disc.tracks.firstWhere((t) => t.isData);
final sector = disc.readSector(disc.tracks.indexOf(track), 16); // 2048 bytes
disc.close();
```

`ChdDisc.openFd` exists for Android, where a ROM is a SAF `content://` URI with
no filesystem path libchdr could open.

## Vendored sources

`src/libchdr/` is [libchdr](https://github.com/rtissera/libchdr) (BSD-3-Clause),
at the commit recorded in `src/libchdr/VENDORED.txt`, together with the three
dependencies it vendors itself: LZMA (public domain), miniz (MIT) and zstd
(BSD-3-Clause). Only the decoder halves are compiled.

Updating it is a directory swap: replace `src/libchdr/`, keeping `VENDORED.txt`
current. All four platforms build through libchdr's own `unity.c` amalgamation,
so nothing else lists its source files.

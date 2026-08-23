/// How a system's ROMs are hashed for RetroAchievements, and whether a failed
/// hash lookup may fall back to guessing by filename.
///
/// The policy is data, not code: it is declared per system in
/// `assets/systems/<sys>.json` under `system.ra_hash`, stored on `app_systems`,
/// and reaches existing installs through the systems OTA update. It used to be
/// three hardcoded lists in the hash service that could — and did — disagree
/// with each other.
library;

/// The hashing algorithm RetroAchievements expects for a system.
///
/// The names are the contract with `assets/systems/<sys>.json`; the mapping from
/// a name to an implementation stays in Dart, so a *new* algorithm still needs
/// an app release while assigning an *existing* one to a system does not.
enum RaHashAlgo {
  /// MD5 of the whole file. What RA uses for most cartridge systems.
  file('file'),

  /// Skips the 16-byte iNES / FDS header when present.
  nes('nes'),

  /// Skips a 512-byte copier header when present.
  snes('snes'),

  /// Header, ARM9, ARM7 and icon regions only.
  ds('ds'),

  /// Byte-order normalized before hashing.
  n64('n64'),

  /// Skips the 64-byte LNX header when present.
  lynx('lynx'),

  /// Skips the 128-byte A78 header when present.
  atari7800('atari7800'),

  /// Hashes the `.hex` record payload.
  arduboy('arduboy'),

  /// MD5 of the MAME short name, not of any file content. Archives are left
  /// packed, because the archive *is* the ROM as far as RA is concerned.
  arcade('arcade'),

  /// PlayStation: the boot executable named by `SYSTEM.CNF`, hashed with its
  /// own filename.
  psx('psx'),

  /// PlayStation 2: the same, from the `BOOT2` key.
  ps2('ps2'),

  /// PSP: `PARAM.SFO` followed by `EBOOT.BIN`.
  psp('psp'),

  /// Sega CD: the disc's first 512 bytes, which hold the volume and ROM
  /// headers.
  segacd('segacd'),

  /// Saturn: the same 512 bytes, under its own name because a system's JSON
  /// should read as the console it is.
  saturn('saturn'),

  /// PC Engine CD: the boot header in sector 1 and the program it points at.
  pcecd('pcecd');

  const RaHashAlgo(this.jsonName);

  /// The value written in `assets/systems/<sys>.json`.
  final String jsonName;

  /// Whether the hash covers something *inside* a disc image rather than the
  /// file itself.
  ///
  /// Disc systems need their own reader, are exempt from the file size cap that
  /// protects the cartridge path — nothing reads a whole disc — and their ROMs
  /// are the ones the bulk pass used to park as unhashable.
  bool get isDisc => switch (this) {
    RaHashAlgo.psx ||
    RaHashAlgo.ps2 ||
    RaHashAlgo.psp ||
    RaHashAlgo.segacd ||
    RaHashAlgo.saturn ||
    RaHashAlgo.pcecd => true,
    _ => false,
  };

  /// The names of every disc algorithm, for the SQL that has to select the
  /// systems using one.
  static List<String> get discJsonNames => RaHashAlgo.values
      .where((algo) => algo.isDisc)
      .map((algo) => algo.jsonName)
      .toList(growable: false);

  /// Parses [value], falling back to [RaHashAlgo.file] for anything unknown —
  /// an older build reading a newer systems JSON, or a system that declares no
  /// policy at all.
  static RaHashAlgo fromJson(String? value) {
    if (value == null) return RaHashAlgo.file;
    final lower = value.toLowerCase();
    for (final algo in RaHashAlgo.values) {
      if (algo.jsonName == lower) return algo;
    }
    return RaHashAlgo.file;
  }
}

/// What a system may do when the hash lookup finds nothing.
enum RaMatchMode {
  /// Hash or nothing. Correct wherever RA registers real hashes: a filename
  /// guess there is a false positive waiting to happen, and the ROMs it would
  /// reach are hacks and bad dumps whose sets are not earnable anyway.
  hashOnly('hash_only'),

  /// May fall back to a sanitized-filename lookup and then to the user's
  /// recently-played history. For systems with no usable hash algorithm.
  filenameFallback('filename_fallback');

  const RaMatchMode(this.jsonName);

  /// The value written in `assets/systems/<sys>.json`.
  final String jsonName;

  /// Parses [value], falling back to [RaMatchMode.filenameFallback] — the
  /// permissive option, so a system whose policy did not survive an OTA round
  /// trip still gets its old best-effort matching rather than none.
  static RaMatchMode fromJson(String? value) {
    if (value == null) return RaMatchMode.filenameFallback;
    final lower = value.toLowerCase();
    for (final mode in RaMatchMode.values) {
      if (mode.jsonName == lower) return mode;
    }
    return RaMatchMode.filenameFallback;
  }
}

/// A system's complete RetroAchievements hashing policy.
class RaHashPolicy {
  /// Which algorithm produces the hash RA would recognise.
  final RaHashAlgo algo;

  /// Whether a failed lookup may guess by filename.
  final RaMatchMode mode;

  const RaHashPolicy({required this.algo, required this.mode});

  /// What a system with no declared policy gets: hash the whole file, and fall
  /// back to filename matching. This is what every unlisted system did before
  /// the policy became data, so an absent declaration changes nothing.
  static const RaHashPolicy fallback = RaHashPolicy(
    algo: RaHashAlgo.file,
    mode: RaMatchMode.filenameFallback,
  );

  /// Reads the policy from the stored algo/mode names.
  factory RaHashPolicy.fromNames(String? algo, String? mode) {
    return RaHashPolicy(
      algo: RaHashAlgo.fromJson(algo),
      mode: RaMatchMode.fromJson(mode),
    );
  }

  /// Whether this system matches by hash alone.
  bool get isHashOnly => mode == RaMatchMode.hashOnly;

  /// Whether archives must be left packed, because the archive name is what
  /// gets hashed.
  bool get keepsArchivesPacked => algo == RaHashAlgo.arcade;

  @override
  bool operator ==(Object other) =>
      other is RaHashPolicy && other.algo == algo && other.mode == mode;

  @override
  int get hashCode => Object.hash(algo, mode);

  @override
  String toString() => 'RaHashPolicy(${algo.jsonName}, ${mode.jsonName})';
}

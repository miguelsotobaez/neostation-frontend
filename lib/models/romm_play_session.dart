/// A single finished play session, as exchanged with RomM's `/api/play-sessions`.
///
/// RomM has no aggregate "total playtime" field — a ROM's playtime is the sum
/// of the sessions its users have reported. So both directions of playtime sync
/// speak in sessions: we POST the ones played here and GET the full list to see
/// what was played elsewhere.
class RommPlaySession {
  /// Server-assigned id. Null for a session we're about to upload.
  final int? id;

  /// RomM ROM id the session belongs to.
  final int romId;

  /// Device the session was reported from. RomM only keeps this for devices
  /// registered through its device-auth flow; sessions we push over a plain
  /// user token come back with a null `device_id`.
  final String? deviceId;

  final DateTime startTime;
  final DateTime endTime;
  final int durationMs;

  const RommPlaySession({
    this.id,
    required this.romId,
    required this.startTime,
    required this.endTime,
    required this.durationMs,
    this.deviceId,
  });

  /// Body entry for `POST /api/play-sessions`.
  ///
  /// Times are sent as whole-second UTC: RomM truncates microseconds server
  /// side before its `(rom_id, start_time)` duplicate check, so sending them
  /// would make a re-push of the same session look like a new one.
  Map<String, dynamic> toIngestJson() => {
    'rom_id': romId,
    'start_time': _utcSeconds(startTime),
    'end_time': _utcSeconds(endTime),
    'duration_ms': durationMs,
  };

  static String _utcSeconds(DateTime t) {
    final utc = t.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    ).toIso8601String();
  }

  /// Parses a server timestamp as UTC.
  ///
  /// RomM stores these columns as UTC but serializes them naive
  /// (`2026-07-28T20:00:00`, no `Z` and no offset). [DateTime.parse] reads a
  /// naive string as *local* time, which would shift every pulled session by
  /// the device's UTC offset — enough to write a wrong `last_played`. An
  /// explicit offset, when the server does send one, is honoured.
  static DateTime _parseServerTime(String raw) {
    final value = raw.trim();
    final hasZone =
        value.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value) ||
        // A trailing offset can also follow the time without a separator.
        RegExp(r'T.*[+-]\d{2}$').hasMatch(value);
    return DateTime.parse(hasZone ? value : '${value}Z');
  }

  factory RommPlaySession.fromJson(Map<String, dynamic> json) {
    final start = _parseServerTime(json['start_time'].toString());
    final end = _parseServerTime(json['end_time'].toString());
    return RommPlaySession(
      id: (json['id'] as num?)?.toInt(),
      romId: (json['rom_id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id']?.toString(),
      startTime: start,
      endTime: end,
      durationMs:
          (json['duration_ms'] as num?)?.toInt() ??
          end.difference(start).inMilliseconds,
    );
  }
}

/// Outcome of a `POST /api/play-sessions` batch.
///
/// RomM answers per entry with `created`, `duplicate` (it already had a session
/// with that `(rom_id, start_time)`) or `error` (rejected — e.g. an `end_time`
/// too far in the future for a device with a skewed clock).
class RommPlaySessionIngestResult {
  /// Indexes, into the submitted batch, of the sessions the server now holds —
  /// newly created plus ones it already had. Both count as "ours" for
  /// reconciliation: a duplicate is a session we pushed before but whose
  /// response we lost, and leaving it out would later make our own time look
  /// like another device's and inflate the local total.
  final Set<int> acceptedIndexes;

  /// Indexes the server rejected outright; retrying them would fail again.
  final Set<int> rejectedIndexes;

  final int createdCount;
  final int skippedCount;

  const RommPlaySessionIngestResult({
    required this.acceptedIndexes,
    required this.rejectedIndexes,
    required this.createdCount,
    required this.skippedCount,
  });

  factory RommPlaySessionIngestResult.fromJson(Map<String, dynamic> json) {
    final accepted = <int>{};
    final rejected = <int>{};
    final results = json['results'];
    if (results is List) {
      for (final r in results) {
        if (r is! Map) continue;
        final index = (r['index'] as num?)?.toInt();
        if (index == null) continue;
        if (r['status'] == 'error') {
          rejected.add(index);
        } else {
          accepted.add(index);
        }
      }
    }
    return RommPlaySessionIngestResult(
      acceptedIndexes: accepted,
      rejectedIndexes: rejected,
      createdCount: (json['created_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
    );
  }
}

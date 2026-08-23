import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/romm_asset.dart';
import 'package:neostation/sync/providers/romm_provider.dart';

/// The two rules that let RomM's slot-based saves round-trip to a local disk.
///
/// RomM renames every save uploaded with a `slot` to
/// `<name> [YYYY-MM-DD_HH-MM-SS].<ext>`: the tag is how a slot is versioned
/// server-side, so one save accrues many rows and filenames are deliberately not
/// the identity. Locally they are the *whole* identity — RetroArch loads
/// `<rom>.srm` and nothing else — so a tagged file written to disk is inert, the
/// game boots a fresh save, and the post-close hook uploads that blank file as
/// the copy every device then syncs from. Every step reports success (issue
/// #367; on the reporting instance 112 of 122 saves were server-tagged).
///
/// [RomMSyncProvider.localNameForAsset] undoes the tag, and
/// [RomMSyncProvider.latestPerLocalName] collapses the version history a slot
/// accrues down to the one row that represents the local file.
void main() {
  RommAsset asset(
    String fileName, {
    int id = 1,
    bool isState = false,
    DateTime? updatedAt,
    String? slot,
  }) => RommAsset(
    id: id,
    fileName: fileName,
    fileSizeBytes: 1,
    isState: isState,
    updatedAt: updatedAt,
    slot: slot,
  );

  group('localNameForAsset', () {
    test('strips RomM\'s datetime tag from a slotted save', () {
      expect(
        RomMSyncProvider.localNameForAsset(
          asset('Pokemon Red [2026-07-24_01-20-16].srm', slot: 'autosave'),
        ),
        'Pokemon Red.srm',
      );
    });

    test('keeps a permanent bracket tag that is part of the name', () {
      // The trap in RomM's own `file_name_no_tags`, whose TAG_GROUP_REGEX strips
      // *every* trailing bracket group and would return "Pokemon - Pisces".
      // `[Hack]` is part of the filename RetroArch expects.
      expect(
        RomMSyncProvider.localNameForAsset(
          asset('Pokemon - Pisces [Hack] [2026-07-24_01-20-16].srm'),
        ),
        'Pokemon - Pisces [Hack].srm',
      );
    });

    test('leaves an untagged save untouched', () {
      expect(RomMSyncProvider.localNameForAsset(asset('Game.srm')), 'Game.srm');
    });

    test('strips a tag that is not followed by an extension', () {
      expect(
        RomMSyncProvider.localNameForAsset(asset('Game [2026-01-02_03-04-05]')),
        'Game',
      );
    });

    test('strips a tag sitting mid-name, before a trailing extension', () {
      // RetroArch's auto-save-state names carry two extensions, so the tag RomM
      // inserts before the last one lands in the middle of the string.
      expect(
        RomMSyncProvider.localNameForAsset(
          asset('Game.state [2026-01-02_03-04-05].auto'),
        ),
        'Game.state.auto',
      );
    });

    test('leaves a state untouched, brackets and all', () {
      // `/api/states` has no slot parameter and never tags, so a bracketed
      // timestamp in a state's name is the name, not a version tag.
      expect(
        RomMSyncProvider.localNameForAsset(
          asset('Game [2026-07-24_01-20-16].state', isState: true),
        ),
        'Game [2026-07-24_01-20-16].state',
      );
    });

    test('is a no-op on a near-miss that only looks like a tag', () {
      expect(
        RomMSyncProvider.localNameForAsset(asset('Game [2026-07-24].srm')),
        'Game [2026-07-24].srm',
      );
    });
  });

  group('latestPerLocalName', () {
    test('collapses a slot\'s version history to the newest row', () {
      final kept = RomMSyncProvider.latestPerLocalName([
        asset(
          'Game [2026-07-24_01-00-00].srm',
          id: 1,
          updatedAt: DateTime.utc(2026, 7, 24, 1),
        ),
        asset(
          'Game [2026-07-24_03-00-00].srm',
          id: 3,
          updatedAt: DateTime.utc(2026, 7, 24, 3),
        ),
        asset(
          'Game [2026-07-24_02-00-00].srm',
          id: 2,
          updatedAt: DateTime.utc(2026, 7, 24, 2),
        ),
      ]);

      expect(kept.map((a) => a.id), [3]);
    });

    test('collapses a tagged and an untagged asset together, newest wins', () {
      // The migration case: an old untagged NeoStation upload sitting beside a
      // newer slotted lineage. The untagged row stays on the server as a backup
      // but is never paired against again.
      final kept = RomMSyncProvider.latestPerLocalName([
        asset('Game.srm', id: 1, updatedAt: DateTime.utc(2026, 1, 1)),
        asset(
          'Game [2026-07-24_01-20-16].srm',
          id: 2,
          updatedAt: DateTime.utc(2026, 7, 24),
          slot: 'autosave',
        ),
      ]);

      expect(kept.map((a) => a.id), [2]);
    });

    test('keeps the untagged asset when it is the newer one', () {
      final kept = RomMSyncProvider.latestPerLocalName([
        asset(
          'Game [2026-07-24_01-20-16].srm',
          id: 1,
          updatedAt: DateTime.utc(2026, 7, 24),
          slot: 'autosave',
        ),
        asset('Game.srm', id: 2, updatedAt: DateTime.utc(2026, 8, 1)),
      ]);

      expect(kept.map((a) => a.id), [2]);
    });

    test('never collapses a save into a state of the same name', () {
      final kept = RomMSyncProvider.latestPerLocalName([
        asset('Game.srm', id: 1, updatedAt: DateTime.utc(2026, 1, 1)),
        asset(
          'Game.srm',
          id: 2,
          isState: true,
          updatedAt: DateTime.utc(2026, 2, 1),
        ),
      ]);

      expect(kept.map((a) => a.id), [1, 2]);
    });

    test('breaks a timestamp tie on the later asset id', () {
      final stamp = DateTime.utc(2026, 7, 24);
      final kept = RomMSyncProvider.latestPerLocalName([
        asset('Game [2026-07-24_01-20-16].srm', id: 7, updatedAt: stamp),
        asset('Game [2026-07-24_01-20-17].srm', id: 9, updatedAt: stamp),
      ]);

      expect(kept.map((a) => a.id), [9]);
    });

    test('treats a missing timestamp as the oldest', () {
      final kept = RomMSyncProvider.latestPerLocalName([
        asset('Game [2026-07-24_01-20-16].srm', id: 4),
        asset(
          'Game [2026-07-24_01-20-17].srm',
          id: 2,
          updatedAt: DateTime.utc(2026, 7, 24),
        ),
      ]);

      expect(kept.map((a) => a.id), [2]);
    });

    test('passes a listing with nothing to collapse through in order', () {
      final kept = RomMSyncProvider.latestPerLocalName([
        asset('GameA.srm', id: 1, updatedAt: DateTime.utc(2026, 1, 1)),
        asset('GameB.srm', id: 2, updatedAt: DateTime.utc(2026, 1, 2)),
        asset(
          'GameA.state',
          id: 3,
          isState: true,
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      ]);

      expect(kept.map((a) => a.id), [1, 2, 3]);
    });

    test('an empty listing stays empty', () {
      expect(RomMSyncProvider.latestPerLocalName([]), isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/romm_service.dart';
import 'package:neostation/sync/providers/romm_provider.dart';

/// Guards the classification that decides whether a failed RomM save
/// upload/download is a *permission denial* (must abort the sync with an error
/// status) or a transient/IO failure (safely swallowed to a no-op `false`).
///
/// This is the crux of the fix for RomM 5.0's granular permission system: the
/// service layer already re-authenticates and retries once, so any `403` that
/// reaches the provider is a genuine authorization failure — not a stale token.
/// If it were swallowed, a dropped save would masquerade as a clean, up-to-date
/// sync and silently lose the user's progress.
void main() {
  group('RomMSyncProvider.isPermissionDenied', () {
    test('a 403 RommException is a permission denial → sync must error', () {
      expect(
        RomMSyncProvider.isPermissionDenied(
          RommException('Upload failed (403)', statusCode: 403),
        ),
        isTrue,
      );
    });

    test(
      'a 401 RommException is NOT a permission denial (token recoverable)',
      () {
        expect(
          RomMSyncProvider.isPermissionDenied(
            RommException('Unauthorized', statusCode: 401),
          ),
          isFalse,
        );
      },
    );

    test('a 500 RommException is NOT a permission denial (transient)', () {
      expect(
        RomMSyncProvider.isPermissionDenied(
          RommException('Upload failed (500)', statusCode: 500),
        ),
        isFalse,
      );
    });

    test('a RommException with no status is NOT a permission denial', () {
      expect(
        RomMSyncProvider.isPermissionDenied(
          RommException('Cannot reach server'),
        ),
        isFalse,
      );
    });

    test('a non-Romm error (e.g. FileSystemException) is NOT a denial', () {
      expect(
        RomMSyncProvider.isPermissionDenied(const FormatException('bad bytes')),
        isFalse,
      );
    });
  });
}

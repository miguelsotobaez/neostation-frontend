import 'package:flutter/foundation.dart';

import '../repositories/retro_achievements_repository.dart';
import 'global_notification_service.dart';
import 'logger_service.dart';
import 'retroachievements_hash_service.dart';

/// What started a library-wide RetroAchievements pass. The two triggers want
/// genuinely different behaviour, so this is the switch rather than three
/// booleans the callers would have to keep in sync.
enum RaMatchTrigger {
  /// The user pressed Tools -> Match RetroAchievements Games. Reports itself
  /// the moment it starts, says so when there was nothing to do, and reopens
  /// ROMs parked as unhashable — they asked for a retry, so give them one.
  manual,

  /// The startup pass, running unattended after the folder scan. Stays silent
  /// unless it finds real work, and never reopens parked ROMs: on a matched
  /// library that would re-read every unhashable file on every single launch.
  automatic,
}

/// The runner's user-facing strings, resolved by the caller.
///
/// Localization belongs to the UI layer and this is a service, so the strings
/// come in already translated instead of the service reaching for a
/// [BuildContext] it has no business holding.
class RaMatchStrings {
  /// Names the job in the notification bell. The pass can run unattended, so
  /// the per-ROM message alone ("Identifying Game.zip") never says what the
  /// identifying is *for*; the title is what makes an unprompted notification
  /// legible.
  final String title;

  /// Shown during the cheap lookup-only pass.
  final String lookingUp;

  /// Shown during the hashing pass. Contains `{done}` and `{total}`.
  ///
  /// Counted rather than per-ROM: the filename changed tens of times a second
  /// and told the user nothing they could act on.
  final String hashing;

  /// Completion message. Contains `{matched}` and `{hashed}`.
  final String done;

  /// Shown when the pass found nothing to do at all.
  final String nothingToDo;

  /// Shown when the pass was stopped early. Contains `{matched}`.
  final String paused;

  /// Shown when the pass threw. Contains `{error}`.
  final String failed;

  const RaMatchStrings({
    required this.title,
    required this.lookingUp,
    required this.hashing,
    required this.done,
    required this.nothingToDo,
    required this.paused,
    required this.failed,
  });
}

/// Runs the two-pass library-wide RetroAchievements match and reports it
/// through [GlobalNotificationService].
///
/// Lifted out of the Tools screen so the startup pass can share it: the
/// ordering of the two passes, the progress denominator and the completion
/// wording are policy, not widget code, and duplicating them would let the two
/// entry points drift apart.
/// Live progress of a running pass, for UI that wants to show it in place
/// rather than in the notification bell.
///
/// [done] and [total] are null during the cheap lookup pass: it walks every
/// hashed-but-unmatched ROM on every launch and finding nothing is its normal
/// outcome, so counting it out loud would be a large number that means nothing
/// to the user.
class RaMatchProgress {
  final int? done;
  final int? total;

  /// True only for the pass that runs as part of the startup sequence, which
  /// the startup screen waits for.
  ///
  /// The pass that resumes after a game session must NOT set this: it runs
  /// against a library the user is already looking at, and throwing them back
  /// to a splash screen on returning from a game would be a bug, not progress.
  final bool holdsSplash;

  const RaMatchProgress({this.done, this.total, this.holdsSplash = false});
}

class RaLibraryMatchRunner {
  RaLibraryMatchRunner._();

  static final _log = LoggerService.instance;

  /// Non-null exactly while a pass is running. The systems grid shows this as
  /// a row above the (still usable) library, the same way it shows the ROM
  /// scan — which is where someone actually looks when the app has just
  /// started, unlike a bell that has to be clicked.
  static final ValueNotifier<RaMatchProgress?> progress =
      ValueNotifier<RaMatchProgress?>(null);

  /// Notification id, shared by both triggers on purpose: only one pass can be
  /// in flight at a time (the service is single-flight), so they can never
  /// need two bars.
  static const String notificationId = 'rematch_achievements';

  /// Runs the cheap lookup pass, then the hashing pass.
  ///
  /// Returns true when the run was stopped before it finished — the caller may
  /// want to pick it up again, which is how the startup pass survives the user
  /// launching a game halfway through it.
  ///
  /// Never throws: a failure is reported through the notification and reported
  /// back as "not cancelled", because there is nothing left to resume.
  static Future<bool> run({
    required RaMatchStrings strings,
    RaMatchTrigger trigger = RaMatchTrigger.manual,
    bool holdsSplash = false,
    VoidCallback? onProgressStateChanged,
  }) async {
    final manual = trigger == RaMatchTrigger.manual;
    var notificationShown = false;

    // The automatic pass reports through `progress` and the systems grid row.
    // It deliberately does NOT post a running notification: it starts on its
    // own, so a bell pulsing for minutes with a filename churning behind it is
    // noise nobody asked for. Its completion message still goes to the bell.
    // The manual pass keeps its notification — Tools' own inline bar reads the
    // notification's progress, so removing it would blank that row.
    void publish({int? done, int? total}) => progress.value = RaMatchProgress(
      done: done,
      total: total,
      holdsSplash: holdsSplash,
    );
    publish();

    void showOrUpdate({
      required String message,
      required GlobalNotificationType type,
      double? progress,
    }) {
      if (notificationShown) {
        GlobalNotificationService().update(
          id: notificationId,
          message: message,
          type: type,
          progress: progress,
        );
      } else {
        notificationShown = true;
        GlobalNotificationService().show(
          id: notificationId,
          title: strings.title,
          message: message,
          type: type,
          progress: progress,
        );
      }
    }

    try {
      if (manual) {
        // The user just pressed a button; acknowledge it before the first
        // query, rather than after. The automatic pass has nobody waiting on
        // it, so it stays quiet until it knows it has work.
        showOrUpdate(
          message: strings.lookingUp,
          type: GlobalNotificationType.info,
          progress: 0,
        );
      }

      // The pass resumes: hashed ROMs are excluded from the candidate query, so
      // a stopped run picks up where it left off. Report progress against the
      // whole hashable library rather than the work left in this run, or the
      // bar restarts at 0% every time and reads as if nothing was kept.
      final coverage = await RetroAchievementsRepository.getRaHashCoverage();
      final alreadyHashed = coverage.hashed;
      final eligible = coverage.eligible;

      // Cheap pass: no file I/O, just retry the local lookup for ROMs that
      // already carry a hash.
      //
      // "Cheap" is relative: it walks every hashed-but-unmatched ROM, which on
      // a real library is thousands of rows and a couple of seconds, and it
      // finds nothing every time by construction — those ROMs are not in the
      // bundled RA database. It is worth doing after that database changes and
      // pointless otherwise, so an unattended pass runs it only then. The user
      // pressing the Tools button always gets it: they may be trying to repair
      // exactly this.
      final runLookup =
          manual || RetroAchievementsRepository.raSeedChangedThisLaunch;
      final lookup = !runLookup
          ? const RaRematchResult(
              total: 0,
              processed: 0,
              hashed: 0,
              matched: 0,
              skipped: 0,
              cancelled: false,
            )
          : await RetroAchievementsHashService.rematchLibrary(
              mode: RaRematchMode.lookupOnly,
              reopenSkipped: manual,
              onProgress: (processed, total, _) {
                if (total == 0) return;
                publish();
                if (!manual) return;
                showOrUpdate(
                  message: strings.lookingUp,
                  type: GlobalNotificationType.info,
                  progress: eligible > 0 ? alreadyHashed / eligible : null,
                );
              },
            );

      // Expensive pass: hash the ROMs that have never been hashed.
      final hashPass = lookup.cancelled
          ? null
          : await RetroAchievementsHashService.rematchLibrary(
              reopenSkipped: manual,
              onProgress: (processed, total, _) {
                if (total == 0) return;
                publish(done: processed, total: total);
                if (!manual) return;
                showOrUpdate(
                  message: strings.hashing
                      .replaceFirst('{done}', processed.toString())
                      .replaceFirst('{total}', total.toString()),
                  type: GlobalNotificationType.info,
                  progress: eligible > 0
                      ? ((alreadyHashed + processed) / eligible).clamp(0.0, 1.0)
                      : processed / total,
                );
              },
            );

      final matched = lookup.matched + (hashPass?.matched ?? 0);
      final hashed = hashPass?.hashed ?? 0;
      final cancelled = lookup.cancelled || (hashPass?.cancelled ?? false);
      final examined = lookup.total + (hashPass?.total ?? 0);

      if (cancelled) {
        _finish(
          title: strings.title,
          message: strings.paused.replaceFirst('{matched}', matched.toString()),
          type: GlobalNotificationType.info,
          notificationShown: notificationShown,
        );
      } else if (!manual && matched == 0 && hashed == 0) {
        // An automatic pass that produced nothing says nothing.
        //
        // Deliberately keyed on what was *found*, not on how many rows were
        // examined: the lookup pass re-walks every hashed-but-unmatched ROM on
        // every launch and legitimately finds nothing, because those ROMs are
        // not in the bundled RA database at all. On a real library that is
        // thousands of candidates, so `examined == 0` never happens and keying
        // on it posted "Done: 0 game(s) matched, 0 newly identified" on every
        // single launch — exactly the noise this trigger exists to avoid.
        GlobalNotificationService().dismiss(notificationId);
      } else if (examined == 0) {
        // The user pressed a button and deserves an answer, even when the
        // answer is that there was nothing left to check.
        _finish(
          title: strings.title,
          message: strings.nothingToDo,
          type: GlobalNotificationType.info,
          notificationShown: notificationShown,
        );
      } else {
        _finish(
          title: strings.title,
          message: strings.done
              .replaceFirst('{matched}', matched.toString())
              .replaceFirst('{hashed}', hashed.toString()),
          type: matched > 0
              ? GlobalNotificationType.success
              : GlobalNotificationType.info,
          notificationShown: notificationShown,
        );
      }

      return cancelled;
    } catch (e, stackTrace) {
      _log.e(
        'Failed to re-match RetroAchievements: $e',
        stackTrace: stackTrace,
      );
      _finish(
        title: strings.title,
        message: strings.failed.replaceFirst('{error}', e.toString()),
        type: GlobalNotificationType.error,
        notificationShown: notificationShown,
      );
      return false;
    } finally {
      progress.value = null;
      onProgressStateChanged?.call();
    }
  }

  /// Writes the completion message, showing the notification first if the run
  /// never got far enough to raise one.
  static void _finish({
    required String title,
    required String message,
    required GlobalNotificationType type,
    required bool notificationShown,
  }) {
    if (notificationShown) {
      GlobalNotificationService().update(
        id: notificationId,
        message: message,
        type: type,
        progress: null,
      );
    } else {
      GlobalNotificationService().show(
        id: notificationId,
        title: title,
        message: message,
        type: type,
      );
    }
  }
}

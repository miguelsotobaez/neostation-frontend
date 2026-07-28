/// Pure credential-state logic for RetroAchievements auto-login.
///
/// Kept free of database, secure-storage and network dependencies so the
/// decision that can *destroy* a stored API key is directly testable.
library;

/// The outcome of reading one persisted credential.
///
/// [value] is only meaningful when [ok] is true. A failed read must never be
/// collapsed into `null`: "the database was not readable yet" and "the user
/// never signed in" are different states, and treating the first as the second
/// is how a cold boot used to delete a valid API key.
class CredentialRead {
  const CredentialRead.ok(this.value) : ok = true;
  const CredentialRead.failed() : ok = false, value = null;

  /// Whether the underlying storage was readable at all.
  final bool ok;

  /// The stored credential, or null when nothing was stored.
  final String? value;

  /// True only when the storage was readable and held a non-blank value.
  bool get hasValue => ok && (value?.trim().isNotEmpty ?? false);
}

/// What [RetroAchievementsProvider.tryAutoLogin] should do with the
/// credentials it just read.
enum RaAutoLoginAction {
  /// Both credentials are present — authenticate with them.
  attemptLogin,

  /// A key is stored with no username. Older builds persisted the maintainer's
  /// shared API key that way and authenticated everyone's traffic with it; the
  /// v94 migration cleared the username to force a personal-key login. Since
  /// credentials are now always saved and cleared as a pair, this can only be
  /// that orphaned legacy key, so it is dropped.
  clearOrphanedKey,

  /// Nothing usable, or the credentials could not be read. Change nothing.
  skip,
}

/// Decides how to act on the credentials read at startup.
///
/// The critical rule: [RaAutoLoginAction.clearOrphanedKey] is returned only
/// when *both* reads succeeded, so a transient storage failure can never be
/// mistaken for an orphaned legacy key and erase a working account.
RaAutoLoginAction resolveRaAutoLoginAction({
  required CredentialRead user,
  required CredentialRead apiKey,
}) {
  if (!user.ok || !apiKey.ok) return RaAutoLoginAction.skip;
  if (user.hasValue) {
    return apiKey.hasValue
        ? RaAutoLoginAction.attemptLogin
        : RaAutoLoginAction.skip;
  }
  return apiKey.hasValue
      ? RaAutoLoginAction.clearOrphanedKey
      : RaAutoLoginAction.skip;
}

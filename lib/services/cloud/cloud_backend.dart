/// Storage and identity for cloud saves. [FirebaseCloudBackend] is the real
/// implementation; tests use an in-memory fake. Keeping the interface small
/// means the game never depends on Firebase types directly.
abstract interface class CloudBackend {
  /// Signs in (anonymously the first time, the same account afterwards)
  /// and returns the player's account.
  Future<CloudAccount> signIn();

  /// The player's saved document, or null if none exists yet.
  Future<Map<String, Object?>?> fetchSave();

  /// Replaces the player's saved document.
  Future<void> pushSave(Map<String, Object?> save);

  /// Links the current account to Google so progress survives reinstalls
  /// and moves between phones. If that Google account already holds a
  /// save, switches to it instead (the caller then merges both saves).
  Future<CloudAccount> linkGoogle();

  /// Deletes the cloud save and the account (required by store policies).
  Future<void> deleteAccount();
}

class CloudAccount {
  const CloudAccount({required this.uid, this.email, this.linked = false});
  final String uid;

  /// Google account email once linked.
  final String? email;

  /// True when the account is linked to Google (not anonymous only).
  final bool linked;
}

/// Thrown when the user closed the Google sign-in screen.
class CloudCancelled implements Exception {
  const CloudCancelled();
}

/// A cloud operation failed for a reason the player should see, e.g.
/// "Google sign-in is turned off for this game".
class CloudFailure implements Exception {
  const CloudFailure(this.message);
  final String message;

  @override
  String toString() => 'CloudFailure: $message';
}

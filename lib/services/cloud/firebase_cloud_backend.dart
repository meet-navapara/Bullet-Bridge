import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../progress/save_data.dart';
import 'cloud_backend.dart';

/// Cloud saves in Firestore, one document per player:
///
///   players/{uid} = {
///     save: (SaveData JSON), schemaVersion, updatedAtMs,
///     updatedAt: (server timestamp), appVersion, platform
///   }
///
/// Only the signed-in player can read or write their document (see
/// firestore.rules). Firestore's offline cache queues writes made without
/// a connection and sends them later.
class FirebaseCloudBackend implements CloudBackend {
  FirebaseCloudBackend({required this.appVersion, required this.platform});

  final String appVersion;
  final String platform;

  static const collection = 'players';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(collection).doc(uid);

  CloudAccount _account(User user) {
    final google = user.providerData
        .where((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID)
        .firstOrNull;
    return CloudAccount(
      uid: user.uid,
      email: google?.email ?? user.email,
      linked: google != null,
    );
  }

  @override
  Future<CloudAccount> signIn() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return _account(user);
  }

  @override
  Future<Map<String, Object?>?> fetchSave() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snap = await _doc(user.uid).get();
    final save = snap.data()?['save'];
    return save is Map ? save.map((k, v) => MapEntry('$k', v)) : null;
  }

  @override
  Future<void> pushSave(Map<String, Object?> save) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _doc(user.uid).set({
      'save': save,
      'schemaVersion': SaveData.schemaVersion,
      'updatedAtMs': save['updatedAtMs'] ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'appVersion': appVersion,
      'platform': platform,
    });
  }

  @override
  Future<CloudAccount> linkGoogle() async {
    try {
      return await _linkGoogle();
    } on FirebaseAuthException catch (e) {
      throw CloudFailure(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
    'network-request-failed' =>
      'No internet connection. Connect and try again.',
    'operation-not-allowed' || 'admin-restricted-operation' =>
      'Sign-in is turned off for this game right now. Try again later.',
    'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
    'user-disabled' => 'This account has been disabled.',
    _ => 'Google sign-in failed (${e.code}). Try again.',
  };

  Future<CloudAccount> _linkGoogle() async {
    final provider = GoogleAuthProvider();
    var user = _auth.currentUser;
    if (user == null) {
      try {
        user = (await _auth.signInAnonymously()).user!;
      } on FirebaseAuthException catch (e) {
        // Guest accounts switched off: sign in with Google directly.
        if (e.code != 'admin-restricted-operation' &&
            e.code != 'operation-not-allowed') {
          rethrow;
        }
        return _account((await _auth.signInWithProvider(provider)).user!);
      }
    }
    try {
      final result = await user.linkWithProvider(provider);
      return _account(result.user!);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'provider-already-linked':
          return _account(user);
        case 'credential-already-in-use':
        case 'email-already-in-use':
          // This Google account already has a save (another phone or an
          // earlier install): switch to it. The caller merges this
          // device's progress into it, so nothing is lost.
          final credential = e.credential;
          final result = credential != null
              ? await _auth.signInWithCredential(credential)
              : await _auth.signInWithProvider(provider);
          return _account(result.user!);
        case 'web-context-canceled':
        case 'canceled':
        case 'popup-closed-by-user':
          throw const CloudCancelled();
        default:
          rethrow;
      }
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _doc(user.uid).delete();
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // Deleting a long-signed-in account needs a fresh sign-in; the data
      // is already gone, so just sign out.
      if (e.code != 'requires-recent-login') rethrow;
    }
    await _auth.signOut();
  }
}

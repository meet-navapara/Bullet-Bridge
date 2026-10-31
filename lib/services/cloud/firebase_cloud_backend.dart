import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// [GoogleSignIn.initialize] may only run once per app launch.
  static Future<void>? _googleReady;

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
    final user = _auth.currentUser;
    if (user == null) throw const CloudFailure('Not signed in.');
    return _account(user);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await _forgetGoogleAccount();
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

  /// Shows the phone's own Google account sheet, so no web page or Firebase
  /// address appears. The web client ID comes from google-services.json.
  Future<AuthCredential> _googleCredential() async {
    await (_googleReady ??= GoogleSignIn.instance.initialize());
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const CloudFailure('Google sign-in failed. Try again.');
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          throw const CloudCancelled();
        default:
          debugPrint('Google sign-in failed: ${e.code} ${e.description}');
          throw CloudFailure(
            'Google sign-in failed (${e.code.name}). Try again.',
          );
      }
    }
  }

  Future<CloudAccount> _linkGoogle() async {
    final credential = await _googleCredential();
    // Installs from before the welcome screen may still hold an anonymous
    // account: link it, so its cloud save is kept.
    final user = _auth.currentUser;
    try {
      final result = user == null
          ? await _auth.signInWithCredential(credential)
          : await user.linkWithCredential(credential);
      return _account(result.user!);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'provider-already-linked':
          return _account(user!);
        case 'credential-already-in-use':
        case 'email-already-in-use':
          // This Google account already has a save (another phone or an
          // earlier install): switch to it. The caller merges this
          // device's progress into it, so nothing is lost.
          final result = await _auth.signInWithCredential(
            e.credential ?? credential,
          );
          return _account(result.user!);
        default:
          rethrow;
      }
    }
  }

  /// Makes the next sign-in offer the account sheet again.
  Future<void> _forgetGoogleAccount() async {
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize());
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: $e');
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
      if (e.code != 'requires-recent-login') rethrow;
      // A long-signed-in account needs a fresh sign-in to be deleted. If the
      // player refuses, the save is already gone; the website's delete page
      // covers the empty account that remains.
      try {
        await user.reauthenticateWithCredential(await _googleCredential());
        await user.delete();
      } catch (e) {
        debugPrint('Account deletion needs a fresh sign-in: $e');
      }
    }
    await _auth.signOut();
    await _forgetGoogleAccount();
  }
}

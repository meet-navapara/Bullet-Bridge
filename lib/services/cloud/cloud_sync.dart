import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../progress/player_progress.dart';
import '../../progress/save_data.dart';
import '../../progress/save_repository.dart';
import 'cloud_backend.dart';

enum CloudStatus {
  /// Firebase is not configured for this build: local saves only.
  disabled,
  connecting,
  synced,
  syncing,

  /// No connection right now; local progress is safe and syncs later.
  offline,
}

/// Keeps the player's progress in the cloud.
///
/// - On start: signs in, downloads the cloud save, merges it with this
///   device's save ([PlayerProgress.mergeFrom]) and uploads the result.
/// - After every local change (a finished run, a purchase…): uploads,
///   debounced so a burst of changes costs one write.
/// - When the app goes to the background: uploads immediately.
///
/// Local saving never waits for the cloud; every cloud failure leaves the
/// game fully playable and is retried later.
class CloudSync extends ChangeNotifier {
  CloudSync({
    required CloudBackend? backend,
    required this.progress,
    this.debounce = const Duration(seconds: 4),
  }) : _backend = backend,
       _status = backend == null ? CloudStatus.disabled : CloudStatus.offline;

  /// Cloud saves are off (no backend).
  CloudSync.disabled({required this.progress})
    : _backend = null,
      debounce = Duration.zero,
      _status = CloudStatus.disabled;

  final CloudBackend? _backend;
  final PlayerProgress progress;
  final Duration debounce;

  CloudStatus _status;
  CloudStatus get status => _status;
  CloudAccount? _account;
  CloudAccount? get account => _account;
  DateTime? _lastSynced;
  DateTime? get lastSynced => _lastSynced;
  bool get enabled => _backend != null;

  Timer? _timer;
  bool _merging = false;
  bool _dirty = false;
  bool _started = false;
  Future<void>? _inFlight;

  void _set(CloudStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  /// Signs in and performs the first sync. Safe to call more than once.
  Future<void> start() async {
    if (_backend == null) return;
    if (!_started) {
      _started = true;
      progress.addListener(_onLocalChange);
    }
    await syncNow();
  }

  /// Download, merge and upload now.
  Future<void> syncNow() => _serial(() async {
    final backend = _backend;
    if (backend == null) return;
    _set(_account == null ? CloudStatus.connecting : CloudStatus.syncing);
    try {
      _account ??= await backend.signIn();
      await _pullAndMerge(backend);
      await _push(backend);
      _lastSynced = DateTime.now();
      _set(CloudStatus.synced);
    } catch (e) {
      debugPrint('Cloud sync failed: $e');
      _set(CloudStatus.offline);
    }
  });

  /// Uploads pending changes immediately (app going to the background).
  Future<void> flush() async {
    _timer?.cancel();
    if (!_dirty || _account == null) return;
    await _serial(() async {
      final backend = _backend;
      if (backend == null) return;
      try {
        await _push(backend);
        _set(CloudStatus.synced);
      } catch (_) {
        _set(CloudStatus.offline);
      }
    });
  }

  /// Links this player to a Google account. If that account already has
  /// a save, both saves are merged. Returns false if the player cancelled.
  Future<bool> linkGoogle() async {
    final backend = _backend;
    if (backend == null) return false;
    var linked = false;
    await _serial(() async {
      _set(CloudStatus.syncing);
      try {
        _account = await backend.linkGoogle();
        await _pullAndMerge(backend);
        await _push(backend);
        _lastSynced = DateTime.now();
        linked = true;
        _set(CloudStatus.synced);
      } on CloudCancelled {
        _set(CloudStatus.synced);
      } on CloudFailure {
        // Sign-in was refused, but the existing save is still in sync.
        _set(_account == null ? CloudStatus.offline : CloudStatus.synced);
        rethrow;
      } catch (e) {
        debugPrint('Google link failed: $e');
        _set(CloudStatus.offline);
        rethrow;
      }
    });
    notifyListeners();
    return linked;
  }

  /// Deletes the cloud copy and the account. Local progress stays on this
  /// device; a fresh anonymous account is created on the next sync.
  Future<void> deleteCloudData() async {
    final backend = _backend;
    if (backend == null) return;
    await _serial(() async {
      await backend.deleteAccount();
      _account = null;
      _dirty = false;
      _set(CloudStatus.offline);
    });
  }

  Future<void> _pullAndMerge(CloudBackend backend) async {
    final raw = await backend.fetchSave();
    if (raw == null) return;
    final remote = SaveData.fromJson(SaveRepository.migrate(raw));
    _merging = true;
    try {
      await progress.mergeFrom(remote);
    } finally {
      _merging = false;
    }
  }

  Future<void> _push(CloudBackend backend) async {
    _dirty = false;
    await backend.pushSave(progress.data.toJson());
  }

  void _onLocalChange() {
    if (_merging || _backend == null) return;
    _dirty = true;
    if (_account == null) return; // uploaded by the next successful sync
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  /// Runs cloud operations one at a time.
  Future<void> _serial(Future<void> Function() op) {
    final previous = _inFlight ?? Future<void>.value();
    final next = previous.then((_) => op(), onError: (_) => op());
    _inFlight = next.catchError((_) {});
    return next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    progress.removeListener(_onLocalChange);
    super.dispose();
  }
}

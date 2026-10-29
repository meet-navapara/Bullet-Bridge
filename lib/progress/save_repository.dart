import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'save_data.dart';

/// Minimal key-value storage so persistence can be swapped (cloud sync,
/// another database) or faked in tests.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
  Future<void> delete(String key);
}

class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesStore> create() async =>
      SharedPreferencesStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<bool> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

class InMemoryStore implements KeyValueStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

enum LoadSource { primary, backup, fresh }

class LoadResult {
  const LoadResult(this.data, this.source, {this.corruptionDetected = false});
  final SaveData data;
  final LoadSource source;
  final bool corruptionDetected;
}

/// Reads and writes the single versioned save document.
///
/// Each successful write first copies the previous good document to a
/// backup key, so a write interrupted half-way (or a corrupted primary)
/// never loses more than the latest change.
class SaveRepository {
  SaveRepository(this._store);

  static const primaryKey = 'orbit_blast.save';
  static const backupKey = 'orbit_blast.save.backup';

  final KeyValueStore _store;

  Future<LoadResult> load() async {
    final primary = await _safeRead(primaryKey);
    final parsedPrimary = _parse(primary);
    if (parsedPrimary != null) {
      return LoadResult(parsedPrimary, LoadSource.primary);
    }
    final backup = await _safeRead(backupKey);
    final parsedBackup = _parse(backup);
    if (parsedBackup != null) {
      return LoadResult(
        parsedBackup,
        LoadSource.backup,
        corruptionDetected: primary != null,
      );
    }
    return LoadResult(
      SaveData(),
      LoadSource.fresh,
      corruptionDetected: primary != null || backup != null,
    );
  }

  /// Returns false if the document could not be written.
  Future<bool> save(SaveData data) async {
    try {
      final encoded = jsonEncode(data.toJson());
      final previous = await _safeRead(primaryKey);
      if (previous != null && _parse(previous) != null) {
        await _store.write(backupKey, previous);
      }
      return await _store.write(primaryKey, encoded);
    } catch (_) {
      return false;
    }
  }

  Future<void> wipe() async {
    await _store.delete(primaryKey);
    await _store.delete(backupKey);
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  static SaveData? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = migrate(decoded.map((k, v) => MapEntry('$k', v)));
      return SaveData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Upgrades older documents to [SaveData.schemaVersion]. Add a case per
  /// schema bump; never remove old cases.
  static Map<String, Object?> migrate(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    var v = version is num ? version.toInt() : 0;
    final out = Map<String, Object?>.of(json);
    if (v < 1) {
      // Pre-release documents stored settings flat at the top level.
      final settings = <String, Object?>{};
      for (final key in const ['music', 'sfx', 'vibration']) {
        if (out.containsKey(key)) settings[key] = out.remove(key);
      }
      if (settings.isNotEmpty && out['settings'] == null) {
        out['settings'] = settings;
      }
      v = 1;
    }
    if (v < 2) {
      // Schema 2 added campaign progress (stages, stars, best chain).
      // Missing fields take their defaults, so nothing to transform.
      v = 2;
    }
    if (v < 3) {
      // Schema 3: the campaign grew from 10 to 100 levels. Progress, stars
      // and coins carry over unchanged. A player who already beat the old
      // stage 10 boss was paid for it then, so chapter 1's boss reward
      // (coins only) is marked as claimed instead of being paid twice.
      final cleared = out['highestStageCleared'];
      if (cleared is num && cleared >= 10 && out['chapterRewards'] == null) {
        out['chapterRewards'] = [1];
      }
      v = 3;
    }
    out['schemaVersion'] = v;
    return out;
  }
}

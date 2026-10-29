import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/cloud/cloud_backend.dart';
import 'package:orbit_blast/services/cloud/cloud_sync.dart';

/// In-memory stand-in for Firebase: accounts map to saved documents.
class FakeCloud implements CloudBackend {
  final Map<String, Map<String, Object?>> docs = {};
  String? uid;
  bool online = true;
  bool cancelLink = false;
  bool refuseLink = false;
  int pushes = 0;

  /// Google account id → cloud uid it already belongs to.
  final Map<String, String> googleAccounts = {};
  String googleUser = 'g1';

  void _net() {
    if (!online) throw Exception('offline');
  }

  @override
  Future<CloudAccount> signIn() async {
    _net();
    uid ??= 'anon-${docs.length + 1}';
    return CloudAccount(uid: uid!);
  }

  @override
  Future<Map<String, Object?>?> fetchSave() async {
    _net();
    return docs[uid];
  }

  @override
  Future<void> pushSave(Map<String, Object?> save) async {
    _net();
    pushes++;
    docs[uid!] = save;
  }

  @override
  Future<CloudAccount> linkGoogle() async {
    _net();
    if (cancelLink) throw const CloudCancelled();
    if (refuseLink) throw const CloudFailure('Sign-in is turned off.');
    final existing = googleAccounts[googleUser];
    if (existing != null) {
      uid = existing; // credential already in use: switch accounts
    } else {
      googleAccounts[googleUser] = uid!;
    }
    return CloudAccount(uid: uid!, email: '$googleUser@x.com', linked: true);
  }

  @override
  Future<void> deleteAccount() async {
    _net();
    docs.remove(uid);
    googleAccounts.removeWhere((_, v) => v == uid);
    uid = null;
  }
}

PlayerProgress progressWith(SaveData d) =>
    PlayerProgress(SaveRepository(InMemoryStore()), d);

void main() {
  test('first start uploads this device save', () async {
    final cloud = FakeCloud();
    final p = progressWith(SaveData(coins: 50, highestStageCleared: 3));
    final sync = CloudSync(backend: cloud, progress: p);
    await sync.start();
    expect(sync.status, CloudStatus.synced);
    expect(cloud.docs.values.single['highestStageCleared'], 3);
  });

  test('a cloud save is merged into this device on start', () async {
    final cloud = FakeCloud()
      ..uid = 'u1'
      ..docs['u1'] = SaveData(
        highestStageCleared: 20,
        coins: 999,
        updatedAtMs: 99,
      ).toJson();
    final p = progressWith(SaveData(highestStageCleared: 5, updatedAtMs: 1));
    final sync = CloudSync(backend: cloud, progress: p);
    await sync.start();
    expect(p.data.highestStageCleared, 20);
    expect(p.data.coins, 999, reason: 'cloud copy was newer');
    expect(cloud.docs['u1']!['highestStageCleared'], 20);
  });

  test('local changes upload once after the debounce', () async {
    final cloud = FakeCloud();
    final p = progressWith(SaveData());
    final sync = CloudSync(
      backend: cloud,
      progress: p,
      debounce: const Duration(milliseconds: 20),
    );
    await sync.start();
    final before = cloud.pushes;
    await p.updateSettings((s) => s.music = false);
    await p.updateSettings((s) => s.sfx = false);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(cloud.pushes, before + 1, reason: 'two changes, one write');
  });

  test('offline: the game keeps working and syncs later', () async {
    final cloud = FakeCloud()..online = false;
    final p = progressWith(SaveData(coins: 10));
    final sync = CloudSync(backend: cloud, progress: p);
    await sync.start();
    expect(sync.status, CloudStatus.offline);
    expect(await p.updateSettings((s) => s.music = false), isTrue);
    cloud.online = true;
    await sync.syncNow();
    expect(sync.status, CloudStatus.synced);
    expect(cloud.docs.values.single['coins'], 10);
  });

  test('flush uploads pending changes immediately', () async {
    final cloud = FakeCloud();
    final p = progressWith(SaveData());
    final sync = CloudSync(
      backend: cloud,
      progress: p,
      debounce: const Duration(hours: 1),
    );
    await sync.start();
    await p.updateSettings((s) => s.vibration = false);
    final before = cloud.pushes;
    await sync.flush();
    expect(cloud.pushes, before + 1);
  });

  test('signing in with Google on a new phone restores the old save', () async {
    final cloud = FakeCloud();
    // Old phone: progress linked to Google account g1.
    final oldPhone = progressWith(SaveData(highestStageCleared: 40));
    final oldSync = CloudSync(backend: cloud, progress: oldPhone);
    await oldSync.start();
    expect(await oldSync.linkGoogle(), isTrue);

    // New phone: fresh install, new anonymous account, a little progress.
    cloud.uid = null;
    final newPhone = progressWith(
      SaveData(highestStageCleared: 2, updatedAtMs: 5),
    );
    final newSync = CloudSync(backend: cloud, progress: newPhone);
    await newSync.start();
    expect(newPhone.data.highestStageCleared, 2);
    expect(await newSync.linkGoogle(), isTrue);
    expect(newSync.account!.linked, isTrue);
    expect(newPhone.data.highestStageCleared, 40, reason: 'restored');
  });

  test('cancelling Google sign-in changes nothing', () async {
    final cloud = FakeCloud()..cancelLink = true;
    final sync = CloudSync(backend: cloud, progress: progressWith(SaveData()));
    await sync.start();
    expect(await sync.linkGoogle(), isFalse);
    expect(sync.account!.linked, isFalse);
    expect(sync.status, CloudStatus.synced);
  });

  test('a refused Google sign-in reports why and stays synced', () async {
    final cloud = FakeCloud()..refuseLink = true;
    final sync = CloudSync(backend: cloud, progress: progressWith(SaveData()));
    await sync.start();
    await expectLater(
      sync.linkGoogle(),
      throwsA(
        isA<CloudFailure>().having(
          (e) => e.message,
          'message',
          'Sign-in is turned off.',
        ),
      ),
    );
    expect(sync.status, CloudStatus.synced, reason: 'not "Offline"');
    expect(sync.account!.linked, isFalse);
  });

  test('deleting cloud data keeps progress on this device', () async {
    final cloud = FakeCloud();
    final p = progressWith(SaveData(highestStageCleared: 7));
    final sync = CloudSync(backend: cloud, progress: p);
    await sync.start();
    await sync.deleteCloudData();
    expect(cloud.docs, isEmpty);
    expect(sync.account, isNull);
    expect(p.data.highestStageCleared, 7);
  });

  test('without Firebase the sync is disabled and does nothing', () async {
    final p = progressWith(SaveData());
    final sync = CloudSync.disabled(progress: p);
    await sync.start();
    await sync.flush();
    expect(sync.status, CloudStatus.disabled);
    expect(await sync.linkGoogle(), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_merge.dart';
import 'package:orbit_blast/progress/save_repository.dart';

void main() {
  SaveData phoneA() => SaveData(
    coins: 500,
    updatedAtMs: 1000,
    highestStageCleared: 12,
    stageStars: {1: 3, 2: 2, 12: 1},
    levelBest: {12: 900},
    upgrades: {
      ...SaveData.defaultUpgrades(),
      UpgradeType.fireRate: 6,
      UpgradeType.bulletPower: 3,
    },
    ownedSkins: {'cobalt', 'ember'},
    selectedSkin: 'ember',
    chapterRewards: {1},
    claimedAchievements: {'stage_3'},
    committedRuns: {'a1', 'a2'},
    bestScore: 4000,
    tutorialDone: true,
  )..settings.musicVolume = 0.2;

  SaveData phoneB() => SaveData(
    coins: 80,
    updatedAtMs: 2000,
    highestStageCleared: 9,
    stageStars: {1: 1, 2: 3, 9: 3},
    levelBest: {12: 300, 9: 1200},
    upgrades: {
      ...SaveData.defaultUpgrades(),
      UpgradeType.fireRate: 4,
      UpgradeType.bulletPower: 7,
    },
    ownedSkins: {'cobalt', 'storm'},
    selectedSkin: 'storm',
    chapterRewards: {1},
    claimedAchievements: {'first_game'},
    committedRuns: {'b1'},
    bestScore: 6000,
  )..settings.musicVolume = 0.9;

  test('earned progress is never lost', () {
    final m = SaveMerge.merge(phoneA(), phoneB());
    expect(m.highestStageCleared, 12);
    expect(m.stageStars, {1: 3, 2: 3, 9: 3, 12: 1});
    expect(m.levelBest, {12: 900, 9: 1200});
    expect(m.level(UpgradeType.fireRate), 6);
    expect(m.level(UpgradeType.bulletPower), 7);
    expect(m.ownedSkins, {'cobalt', 'ember', 'storm'});
    expect(m.claimedAchievements, {'stage_3', 'first_game'});
    expect(m.bestScore, 6000);
    expect(m.tutorialDone, isTrue);
    expect(m.committedRuns, containsAll(['a1', 'a2', 'b1']));
  });

  test('coins and selections come from the newer save, never added', () {
    final m = SaveMerge.merge(phoneA(), phoneB());
    expect(m.coins, 80, reason: 'B changed last');
    expect(m.selectedSkin, 'storm');
    expect(m.updatedAtMs, 2000);
    final reverse = SaveMerge.merge(phoneB(), phoneA()..updatedAtMs = 3000);
    expect(reverse.coins, 500);
  });

  test('settings always stay as they are on this device', () {
    expect(SaveMerge.merge(phoneA(), phoneB()).settings.musicVolume, 0.2);
    expect(SaveMerge.merge(phoneB(), phoneA()).settings.musicVolume, 0.9);
  });

  test('merging is idempotent and order-independent for progress', () {
    final ab = SaveMerge.merge(phoneA(), phoneB());
    final again = SaveMerge.merge(ab, phoneB());
    expect(again.toJson(), ab.toJson());
    final ba = SaveMerge.merge(phoneB(), phoneA());
    expect(ba.highestStageCleared, ab.highestStageCleared);
    expect(ba.stageStars, ab.stageStars);
    expect(ba.upgrades, ab.upgrades);
  });

  test('run history stays bounded after merging', () {
    final a = SaveData(
      committedRuns: {for (var i = 0; i < 20; i++) 'a$i'},
      updatedAtMs: 1,
    );
    final b = SaveData(
      committedRuns: {for (var i = 0; i < 20; i++) 'b$i'},
      updatedAtMs: 2,
    );
    final m = SaveMerge.merge(a, b);
    expect(m.committedRuns.length, SaveData.committedRunHistory);
  });

  test('PlayerProgress.mergeFrom persists and publishes the merge', () async {
    final store = InMemoryStore();
    final progress = PlayerProgress(SaveRepository(store), phoneA());
    var notified = 0;
    progress.addListener(() => notified++);
    expect(await progress.mergeFrom(phoneB()), isTrue);
    expect(notified, 1);
    expect(progress.data.highestStageCleared, 12);
    final loaded = (await SaveRepository(store).load()).data;
    expect(loaded.level(UpgradeType.bulletPower), 7);
  });

  test('every change stamps the save with the time it was made', () async {
    final progress = PlayerProgress(
      SaveRepository(InMemoryStore()),
      SaveData(),
      clock: () => DateTime.fromMillisecondsSinceEpoch(123456),
    );
    await progress.updateSettings((s) => s.music = false);
    expect(progress.data.updatedAtMs, 123456);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_merge.dart';

int _fieldCount(Object? value) => switch (value) {
  final Map<dynamic, dynamic> m =>
    1 + m.values.fold<int>(0, (sum, v) => sum + _fieldCount(v)),
  final List<dynamic> l => 1 + l.fold<int>(0, (sum, v) => sum + _fieldCount(v)),
  _ => 1,
};

void main() {
  final finished = SaveData(
    highestStageCleared: StageSpec.levelCount,
    stageStars: {for (var l = 1; l <= StageSpec.levelCount; l++) l: 3},
    levelBest: {for (var l = 1; l <= StageSpec.levelCount; l++) l: 999999999},
    chapterRewards: {for (var c = 1; c <= StageSpec.chapters; c++) c},
  );

  test('a finished campaign fits in one Firestore document', () {
    final json = finished.toJson();
    // Firestore allows 1 MiB per document and 40,000 index entries, and each
    // field gets two entries.
    expect(utf8.encode(jsonEncode(json)).length, lessThan(100 * 1024));
    expect(_fieldCount(json) * 2, lessThan(20000));
  });

  test('a finished campaign survives saving and merging', () {
    final restored = SaveData.fromJson(
      jsonDecode(jsonEncode(finished.toJson())) as Map<String, Object?>,
    );
    expect(restored.highestStageCleared, StageSpec.levelCount);
    expect(restored.stageStars[StageSpec.levelCount], 3);

    final merged = SaveMerge.merge(SaveData(), restored);
    expect(merged.highestStageCleared, StageSpec.levelCount);
    expect(merged.stageStars.length, StageSpec.levelCount);
    expect(merged.chapterRewards.length, StageSpec.chapters);
  });
}

// Renders a contact sheet of level skies for visual review, including the
// gameplay objects' sizes for scale. Writes tool/screenshots/out/ambient.png.
//   flutter test tool/screenshots/ambient_gallery_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/config/level_animation.dart';
import 'package:orbit_blast/render/ambient_art.dart';
import 'package:orbit_blast/render/ball_art.dart';
import 'package:orbit_blast/render/world_art.dart';

const levels = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  112,
  345,
  678,
  1000,
];

void main() {
  test('every effect paints at any time without error', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final theme = Campaign.chapter(1).theme;
    for (final main in AmbientKind.values) {
      for (final time in [0.0, 1.3, 77.7, 3600.0]) {
        final animation = LevelAnimation(
          level: 7,
          main: main,
          accent: AmbientKind.values[(main.index + 1) % 24],
          wind: AmbientWind.values[main.index % 4],
          tempo: AmbientTempo.brisk,
        );
        AmbientArt.paintMood(canvas, const Size(390, 844), 760, animation);
        AmbientArt.paint(
          canvas,
          const Size(390, 844),
          760,
          animation,
          theme,
          time,
        );
      }
    }
    recorder.endRecording().dispose();
  });

  test('contact sheet', () async {
    const w = 260.0;
    const h = 440.0;
    const columns = 6;
    final rows = (levels.length / columns).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < levels.length; i++) {
      final level = Campaign.level(levels[i]);
      canvas.save();
      canvas.translate((i % columns) * (w + 6), (i ~/ columns) * (h + 6));
      canvas.clipRect(const Rect.fromLTWH(0, 0, w, h));
      const size = Size(w, h);
      final groundTop = h * (1 - Physics.floorHeight / 760);
      final theme = level.chapterDef.theme;
      WorldArt.paintScene(
        canvas,
        size,
        theme,
        groundTop: groundTop,
        ground: false,
      );
      AmbientArt.paintMood(canvas, size, groundTop, level.animation);
      AmbientArt.paint(canvas, size, groundTop, level.animation, theme, 12.4);
      WorldArt.paintGround(canvas, Rect.fromLTRB(0, groundTop, w, h), theme);
      // A real crystal size, to judge whether the sky competes with it.
      canvas.drawCircle(
        Offset(w * 0.3, h * 0.45),
        BallSpec.radius[2] * w / 360,
        Paint()..color = BallArt.colorForTier(2),
      );
      canvas.restore();
    }
    final image = await recorder.endRecording().toImage(
      (columns * (w + 6)).toInt(),
      (rows * (h + 6)).toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('tool/screenshots/out/ambient.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

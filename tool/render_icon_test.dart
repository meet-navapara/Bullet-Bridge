// Renders the launcher icon from the game's own vector art.
//
// Run from the project root:
//   flutter test tool/render_icon_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/render/cannon_art.dart';
import 'package:orbit_blast/render/crystal_art.dart';
import 'package:orbit_blast/render/world_art.dart';

const double size = 1024;

void main() {
  testWidgets('render launcher icon', (tester) async {
    await tester.runAsync(() async {
      Directory('assets/icon').createSync(recursive: true);
      await _write('assets/icon/icon.png', (c) {
        _background(c);
        _artwork(c);
      });
      // Adaptive icon foreground: artwork scaled into the 66% safe zone.
      await _write('assets/icon/icon_foreground.png', (c) {
        c.translate(size / 2, size / 2);
        c.scale(0.64);
        c.translate(-size / 2, -size / 2);
        _artwork(c);
      });
    });
  });
}

Future<void> _write(String path, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void _background(Canvas c) {
  final theme = Catalog.themes.first;
  WorldArt.paintScene(c, const Size(size, size), theme, groundTop: size * 0.8);
}

void _artwork(Canvas c) {
  // Explosion burst behind the crystal.
  const center = Offset(size * 0.6, size * 0.33);
  final rays = Path();
  for (var i = 0; i < 16; i++) {
    final a = i / 16 * math.pi * 2;
    final r = i.isEven ? size * 0.33 : size * 0.2;
    final p = center + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      rays.moveTo(p.dx, p.dy);
    } else {
      rays.lineTo(p.dx, p.dy);
    }
  }
  rays.close();
  c.drawPath(rays, Paint()..color = const Color(0xFF1C1830));
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(0.88);
  c.translate(-center.dx, -center.dy);
  c.drawPath(
    rays,
    Paint()
      ..shader = ui.Gradient.radial(
        center,
        size * 0.33,
        const [Color(0xFFFFFFFF), Color(0xFFFFE07A), Color(0xFFFF7A2B)],
        const [0, 0.35, 1],
      ),
  );
  c.restore();

  CrystalArt().shard(
    c,
    x: center.dx,
    y: center.dy,
    r: size * 0.17,
    color: const Color(0xFFA766FF),
    text: '',
  );

  // Flying shards.
  for (final (dx, dy, s, col) in [
    (-0.2, -0.16, 0.05, const Color(0xFF3DA9FF)),
    (0.22, 0.12, 0.045, const Color(0xFF34D27A)),
    (0.2, -0.2, 0.035, const Color(0xFFFF4D6A)),
  ]) {
    CrystalArt().shard(
      c,
      x: center.dx + dx * size,
      y: center.dy + dy * size,
      r: size * s,
      color: col,
      text: '',
    );
  }

  // Cannon bolt heading for the crystal.
  final bolt = Path()
    ..moveTo(size * 0.47, size * 0.5)
    ..lineTo(size * 0.5, size * 0.58)
    ..lineTo(size * 0.44, size * 0.58)
    ..close();
  c.drawPath(bolt, Paint()..color = const Color(0xFFFFE14A));

  CannonArt.draw(
    c,
    x: size * 0.43,
    baseY: size * 0.93,
    skin: Catalog.skins.first,
    level: 4,
    scale: size * 0.0058,
    glowPulse: 1,
    tilt: 0.12,
    core: const Color(0xFFFF7A2B),
    muzzleFlash: 1,
  );
}

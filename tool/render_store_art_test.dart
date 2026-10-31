// Renders the Google Play listing art into store/ from the game's own art:
// the 512x512 icon, the 1024x500 feature graphic, and flattened screenshots
// (Play needs PNGs without an alpha channel).
//
// Run from the project root, screenshots first:
//   $env:STORE_SHOTS=1; flutter test tool/screenshots/screenshots_test.dart --update-goldens
//   flutter test tool/render_store_art_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// `image` comes with flutter_launcher_icons; this tool is its only other user.
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/render/cannon_art.dart';
import 'package:orbit_blast/render/crystal_art.dart';
import 'package:orbit_blast/render/world_art.dart';

const Size graphic = Size(1024, 500);

void main() {
  testWidgets('render store art', (tester) async {
    await tester.runAsync(() async {
      final bytes = File('assets/fonts/LilitaOne-Regular.ttf')
          .readAsBytesSync();
      final loader = FontLoader('LilitaOne')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();

      Directory('store/screenshots').createSync(recursive: true);

      final icon = img.decodePng(
        File('assets/icon/icon.png').readAsBytesSync(),
      )!;
      File('store/icon-512.png').writeAsBytesSync(
        img.encodePng(
          img.copyResize(
            icon,
            width: 512,
            height: 512,
            interpolation: img.Interpolation.average,
          ),
        ),
      );

      await _writeGraphic('store/feature-graphic.png');

      for (final file in Directory('store/screenshots').listSync()) {
        if (file is File && file.path.endsWith('.png')) {
          final shot = img.decodePng(file.readAsBytesSync())!;
          file.writeAsBytesSync(img.encodePng(shot.convert(numChannels: 3)));
        }
      }
    });
  });
}

Future<void> _writeGraphic(String path) async {
  final recorder = ui.PictureRecorder();
  _paintGraphic(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    graphic.width.toInt(),
    graphic.height.toInt(),
  );
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: raw!.buffer,
    numChannels: 4,
  );
  File(path).writeAsBytesSync(img.encodePng(rgba.convert(numChannels: 3)));
}

void _paintGraphic(Canvas c) {
  WorldArt.paintScene(c, graphic, Catalog.themes.first, groundTop: 415);

  // Explosion and crystals on the right, as on the launcher icon.
  const center = Offset(800, 165);
  final burst = Path();
  for (var i = 0; i < 16; i++) {
    final a = i / 16 * math.pi * 2;
    final r = i.isEven ? 150.0 : 92.0;
    final p = center + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? burst.moveTo(p.dx, p.dy) : burst.lineTo(p.dx, p.dy);
  }
  burst.close();
  c.drawPath(
    burst,
    Paint()
      ..shader = ui.Gradient.radial(
        center,
        150,
        const [Color(0xFFFFFFFF), Color(0xFFFFE07A), Color(0xFFFF7A2B)],
        const [0, 0.35, 1],
      ),
  );
  for (final (x, y, r, color) in [
    (center.dx, center.dy, 74.0, const Color(0xFFA766FF)),
    (660.0, 90.0, 30.0, const Color(0xFF3DA9FF)),
    (945.0, 250.0, 28.0, const Color(0xFF34D27A)),
    (950.0, 70.0, 22.0, const Color(0xFFFF4D6A)),
  ]) {
    CrystalArt().shard(c, x: x, y: y, r: r, color: color, text: '');
  }

  CannonArt.draw(
    c,
    x: 745,
    baseY: 462,
    skin: Catalog.skins.first,
    level: 4,
    scale: 2.1,
    glowPulse: 1,
    tilt: 0.1,
    core: const Color(0xFFFF7A2B),
    muzzleFlash: 1,
  );

  // Logo, in the colours of the in-game title.
  const left = 48.0;
  final boom = _word(c, 'BOOM', left, 92, const [
    Color(0xFFFFD23F),
    Color(0xFFFF7A1A),
  ]);
  _word(c, 'FORGE', left + boom + 2, 92, const [
    Color(0xFFD6ECFF),
    Color(0xFF3D8BFF),
  ]);

  final ribbon = TextPainter(
    textDirection: TextDirection.ltr,
    text: const TextSpan(
      text: 'BREAK THE WORLD',
      style: TextStyle(
        fontFamily: 'LilitaOne',
        fontSize: 30,
        letterSpacing: 2,
        color: Colors.white,
      ),
    ),
  )..layout();
  final box = RRect.fromRectAndRadius(
    Rect.fromLTWH(left + 6, 210, ribbon.width + 44, ribbon.height + 18),
    const Radius.circular(8),
  );
  c.drawRRect(box.inflate(4), Paint()..color = const Color(0xFF1C1830));
  c.drawRRect(box, Paint()..color = const Color(0xFFFF5A67));
  ribbon.paint(c, Offset(left + 28, 219));
}

/// Draws a word with a dark outline and returns its width.
double _word(Canvas c, String word, double x, double y, List<Color> colors) {
  TextPainter painter(Paint paint) => TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: word,
      style: TextStyle(
        fontFamily: 'LilitaOne',
        fontSize: 98,
        foreground: paint,
      ),
    ),
  )..layout();

  painter(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF1C1830),
  ).paint(c, Offset(x, y));
  final fill = painter(
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, y + 16),
        Offset(0, y + 100),
        colors,
      ),
  )..paint(c, Offset(x, y));
  return fill.width;
}

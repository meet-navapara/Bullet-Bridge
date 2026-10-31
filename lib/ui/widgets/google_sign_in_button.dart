import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_button.dart';

/// The Google sign-in button, the same on the welcome screen and in Settings.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Google',
    this.height = 56,
    this.fontSize = 20,
  });

  final VoidCallback? onPressed;
  final String label;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => GameButton(
    label: label,
    tone: ButtonTone.white,
    height: height,
    fontSize: fontSize,
    icon: ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(height * 0.46),
        painter: _GoogleMarkPainter(),
      ),
    ),
    onPressed: onPressed,
  );
}

/// Google's four-colour "G", drawn so no image asset is needed.
class _GoogleMarkPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    double rad(double degrees) => degrees * math.pi / 180;
    void arc(Color color, double from, double to) => canvas.drawArc(
      rect,
      rad(from),
      rad(to - from),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    arc(const Color(0xFFEA4335), 215, 318);
    arc(const Color(0xFFFBBC05), 145, 215);
    arc(const Color(0xFF34A853), 40, 145);
    arc(_blue, 0, 40);
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * 0.5,
        size.height * 0.5 - stroke / 2,
        size.width,
        size.height * 0.5 + stroke / 2,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}

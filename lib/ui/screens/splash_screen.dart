import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/app_config.dart';
import '../../economy/catalog.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

/// Shows the logo while services load. Always finishes: initialisation has
/// a timeout and errors offer a retry instead of an endless spinner.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.bootstrap,
    required this.onReady,
  });

  final Future<AppServices> Function() bootstrap;
  final void Function(AppServices services) onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    _bar.forward(from: 0);
    try {
      final minimumShowTime = Future<void>.delayed(
        const Duration(milliseconds: 1200),
      );
      final services = await widget.bootstrap().timeout(
        AppConfig.initTimeout + const Duration(seconds: 4),
      );
      await minimumShowTime;
      if (mounted) widget.onReady(services);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the game.\n$e');
    }
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WorldBackground(
        theme: Catalog.theme(Catalog.defaultThemeId),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xxl),
            child: Column(
              children: [
                const Spacer(flex: 3),
                const GameLogo(size: 84),
                const Spacer(flex: 3),
                if (_error == null) ...[
                  AnimatedBuilder(
                    animation: _bar,
                    builder: (context, _) => ProgressBar(
                      value: Curves.easeOut.transform(_bar.value),
                      color: Palette.cyan,
                      height: 14,
                    ),
                  ),
                  const SizedBox(height: Gaps.md),
                  Text(
                    'Loading...',
                    style: TextStyles.body.copyWith(color: Palette.textMuted),
                  ),
                ] else ...[
                  Text(
                    _error!,
                    style: TextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gaps.lg),
                  // Retry works without services, so play no click sound.
                  GameButton(label: 'Retry', silent: true, onPressed: _start),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

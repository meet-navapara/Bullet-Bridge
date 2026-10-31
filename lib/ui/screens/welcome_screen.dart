import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../economy/catalog.dart';
import '../../services/cloud/cloud_backend.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';
import '../widgets/google_sign_in_button.dart';
import 'legal_screen.dart';

/// First launch: the player chooses how to play, knowing what each choice
/// means, before any account exists or anything leaves the device. Either
/// choice can be changed later in Settings > Cloud Save.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  /// The choice is saved; the app can move on to the main menu.
  final VoidCallback onDone;

  /// Share of the screen that is grass, as on the main menu but taller: the
  /// panel sits on it.
  static const double _groundFraction = 0.46;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final linked = await AppScope.of(context).signInWithGoogle();
      if (!mounted) return;
      if (linked) {
        widget.onDone();
        return;
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          e is CloudFailure ? e.message : 'Could not sign in. Check your connection, or continue as a guest.',
          color: Palette.coral,
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _guest() async {
    setState(() => _busy = true);
    await AppScope.of(context).continueAsGuest();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final caption = TextStyles.caption.copyWith(height: 1.3);
    return Scaffold(
      body: WorldBackground(
        theme: Catalog.theme(Catalog.defaultThemeId),
        groundFraction: WelcomeScreen._groundFraction,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final w = constraints.maxWidth;
              final pad = MediaQuery.paddingOf(context);
              final compact = h < 640;
              // Grass line in this SafeArea's coordinates (the world is
              // painted behind the whole screen, including insets).
              final groundTop =
                  (h + pad.top + pad.bottom) *
                      (1 - WelcomeScreen._groundFraction) -
                  pad.top;
              final cannonSize = (h * 0.22).clamp(90.0, w * 0.42);
              return Stack(
                children: [
                  // The cannon, parked on the grass. Small phones need the
                  // room for the panel.
                  if (!compact)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: groundTop - cannonSize * 0.97,
                      child: Center(
                        child: CannonPreview(
                          skin: Catalog.skins.first,
                          size: cannonSize,
                        ),
                      ),
                    ),
                  Positioned(
                    left: Gaps.lg,
                    right: Gaps.lg,
                    top: compact ? Gaps.md : Gaps.xxl,
                    child: GameLogo(size: compact ? 52 : 70),
                  ),
                  Positioned(
                    left: Gaps.lg,
                    right: Gaps.lg,
                    bottom: Gaps.md,
                    child: GamePanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ready to play?',
                            textAlign: TextAlign.center,
                            style: TextStyles.heading,
                          ),
                          const SizedBox(height: Gaps.md),
                          GoogleSignInButton(
                            label: _busy
                                ? 'Please wait…'
                                : 'Continue with Google',
                            onPressed: _busy ? null : _google,
                          ),
                          const SizedBox(height: Gaps.sm),
                          GameButton(
                            label: 'Continue as Guest',
                            fontSize: 20,
                            onPressed: _busy ? null : _guest,
                          ),
                          const SizedBox(height: Gaps.md),
                          Text(
                            'Google keeps your progress on any phone. As a '
                            'guest, it stays on this phone only. You can sign '
                            'in later.',
                            textAlign: TextAlign.center,
                            style: caption,
                          ),
                          const SizedBox(height: Gaps.sm),
                          Text(
                            'By continuing you agree to our',
                            textAlign: TextAlign.center,
                            style: caption,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _LegalLink(
                                  'Terms of Service',
                                  LegalDoc.terms,
                                ),
                                Text(' and ', style: caption),
                                const _LegalLink(
                                  'Privacy Policy',
                                  LegalDoc.privacy,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink(this.label, this.doc);
  final String label;
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => LegalScreen.open(context, doc),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
          child: Text(
            label,
            style: TextStyles.caption.copyWith(
              color: Palette.yellow,
              decoration: TextDecoration.underline,
              decorationColor: Palette.yellow,
            ),
          ),
        ),
      ),
    );
  }
}

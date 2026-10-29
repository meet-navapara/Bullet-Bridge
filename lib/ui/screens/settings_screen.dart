import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';
import '../../config/app_config.dart';
import '../../progress/save_data.dart';
import '../theme/palette.dart';
import '../widgets/cloud_save_panel.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';
import 'legal_screen.dart';
import 'tutorial_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openLegal(BuildContext context, LegalDoc doc) async {
    final url = doc == LegalDoc.privacy
        ? AppConfig.privacyPolicyUrl
        : AppConfig.termsUrl;
    if (url.isNotEmpty) {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);
      if (ok) return;
    }
    if (context.mounted) {
      Navigator.of(context).push(gameRoute<void>(LegalScreen(doc: doc)));
    }
  }

  Future<void> _reset(BuildContext context) async {
    final progress = AppScope.of(context).progress;
    final ok = await confirmDialog(
      context,
      title: 'Reset progress?',
      message: 'This permanently deletes your coins, upgrades, skins, best score and missions. Settings are kept. This cannot be undone.',
      confirmLabel: 'Reset everything',
    );
    if (!ok || !context.mounted) return;
    final really = await confirmDialog(
      context,
      title: 'Are you sure?',
      message: 'Last chance — all progress will be lost.',
      confirmLabel: 'Yes, reset',
    );
    if (!really) return;
    final done = await progress.resetProgress();
    if (context.mounted) {
      showToast(
        context,
        done ? 'Progress reset.' : 'Could not reset. Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final progress = services.progress;
    return ScreenShell(
      title: 'Settings',
      showCoins: false,
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final s = progress.data.settings;
          void update(void Function(GameSettings) f) =>
              progress.updateSettings(f);
          // Hear the new volume while dragging, without saving it yet.
          void preview(void Function(GameSettings) f) {
            final draft = GameSettings.fromJson(s.toJson());
            f(draft);
            services.audio.applySettings(draft);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Gaps.lg,
              Gaps.sm,
              Gaps.lg,
              Gaps.xl,
            ),
            children: [
              GamePanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gaps.lg,
                  vertical: Gaps.sm,
                ),
                child: Column(
                  children: [
                    _SwitchRow(
                      label: 'Music',
                      value: s.music,
                      onChanged: (v) => update((x) => x.music = v),
                    ),
                    _SliderRow(
                      label: 'Music volume',
                      value: s.musicVolume,
                      enabled: s.music,
                      onPreview: (v) => preview((x) => x.musicVolume = v),
                      onChanged: (v) => update((x) => x.musicVolume = v),
                    ),
                    _SwitchRow(
                      label: 'Sound Effects',
                      value: s.sfx,
                      onChanged: (v) => update((x) => x.sfx = v),
                    ),
                    _SliderRow(
                      label: 'Effects volume',
                      value: s.sfxVolume,
                      enabled: s.sfx,
                      onPreview: (v) => preview((x) => x.sfxVolume = v),
                      onChanged: (v) => update((x) => x.sfxVolume = v),
                    ),
                    _SwitchRow(
                      label: 'Vibration',
                      value: s.vibration,
                      onChanged: (v) => update((x) => x.vibration = v),
                    ),
                    _SwitchRow(
                      label: 'Reduced Motion',
                      subtitle: 'Fewer particles, no screen shake',
                      value: s.reducedMotion,
                      onChanged: (v) => update((x) => x.reducedMotion = v),
                    ),
                    _SwitchRow(
                      label: 'Share Usage Data',
                      subtitle: 'Anonymous stats and crash reports',
                      value: s.shareUsageData,
                      onChanged: (v) => update((x) => x.shareUsageData = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.lg),
              const CloudSavePanel(),
              const SizedBox(height: Gaps.lg),
              GamePanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gaps.sm,
                  vertical: Gaps.xs,
                ),
                child: Column(
                  children: [
                    _LinkRow(
                      label: 'How to Play',
                      onTap: () => Navigator.of(context).push(
                        gameRoute<void>(
                          TutorialScreen(
                            onFinished: (ctx) => Navigator.of(ctx).pop(),
                          ),
                        ),
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: services.ads.isPrivacyOptionsRequired(),
                      builder: (context, snap) => snap.data == true
                          ? _LinkRow(
                              label: 'Ad Privacy Choices',
                              onTap: services.ads.showPrivacyOptions,
                            )
                          : const SizedBox.shrink(),
                    ),
                    _LinkRow(
                      label: 'Privacy Policy',
                      onTap: () => _openLegal(context, LegalDoc.privacy),
                    ),
                    _LinkRow(
                      label: 'Terms of Service',
                      onTap: () => _openLegal(context, LegalDoc.terms),
                    ),
                    _LinkRow(
                      label: 'Delete Account & Data',
                      onTap: () => launchUrl(
                        Uri.parse(AppConfig.deleteAccountUrl),
                        mode: LaunchMode.externalApplication,
                      ).catchError((_) => false),
                    ),
                    _LinkRow(
                      label: 'Licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppConfig.title,
                        applicationVersion: services.version,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.lg),
              GameButton(
                label: 'Reset Progress',
                tone: ButtonTone.red,
                height: 48,
                fontSize: 18,
                onPressed: () => _reset(context),
              ),
              const SizedBox(height: Gaps.lg),
              Center(
                child: Text(
                  'Version ${services.version}',
                  style: TextStyles.caption,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyles.body),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyles.caption),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Follows the finger locally (with a live [onPreview]) and saves once, on
/// release. Saving on every drag tick queued dozens of disk writes and made
/// the thumb lag behind the finger.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPreview,
    required this.onChanged,
  });
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(widget.label, style: TextStyles.caption),
        ),
        Expanded(
          child: Slider(
            value: _dragging ?? widget.value,
            label: widget.label,
            onChanged: widget.enabled
                ? (v) {
                    setState(() => _dragging = v);
                    widget.onPreview(v);
                  }
                : null,
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyles.body)),
              const Icon(Icons.chevron_right_rounded, color: Palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

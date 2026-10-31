import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../services/cloud/cloud_backend.dart';
import '../../services/cloud/cloud_sync.dart';
import '../theme/palette.dart';
import 'common.dart';
import 'game_button.dart';
import 'google_sign_in_button.dart';

/// Settings section for cloud saves: status, Google sign-in (so progress
/// survives reinstalls and moves to new phones), manual sync and deleting
/// the cloud copy.
class CloudSavePanel extends StatelessWidget {
  const CloudSavePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final cloud = services.cloud;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final account = cloud.account;
        final (icon, color, text) = switch (cloud.status) {
          CloudStatus.disabled => (
            Icons.cloud_off_rounded,
            Palette.textMuted,
            'Cloud save is not available in this build. Progress is saved on this device.',
          ),
          CloudStatus.signedOut => (
            Icons.person_outline_rounded,
            Palette.textMuted,
            'Playing as a guest. Progress stays on this phone and is lost if you uninstall. Sign in to keep it on any phone.',
          ),
          CloudStatus.connecting || CloudStatus.syncing => (
            Icons.cloud_sync_rounded,
            Palette.cyan,
            'Syncing…',
          ),
          CloudStatus.synced => (
            Icons.cloud_done_rounded,
            Palette.green,
            account?.linked == true
                ? 'Saved to your Google account${account?.email == null ? '' : ' (${account!.email})'}.'
                : 'Saved to the cloud. Sign in to keep it if you reinstall or change phones.',
          ),
          CloudStatus.offline => (
            Icons.cloud_queue_rounded,
            Palette.yellow,
            'Offline. Progress is safe on this device and syncs when you are back online.',
          ),
        };
        return GamePanel(
          padding: const EdgeInsets.all(Gaps.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(width: Gaps.sm),
                  Text('Cloud Save', style: TextStyles.body),
                ],
              ),
              const SizedBox(height: Gaps.xs),
              Text(text, style: TextStyles.caption),
              if (account != null) ...[
                const SizedBox(height: Gaps.xs),
                // Quoted in deletion requests from the website.
                SelectableText(
                  'Player ID: ${account.uid}',
                  style: TextStyles.caption.copyWith(
                    color: Palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
              if (cloud.enabled) ...[
                const SizedBox(height: Gaps.md),
                if (account?.linked != true)
                  GoogleSignInButton(
                    height: 46,
                    fontSize: 17,
                    onPressed:
                        cloud.status == CloudStatus.syncing ||
                            cloud.status == CloudStatus.connecting
                        ? null
                        : () => _link(context),
                  ),
                if (account != null) ...[
                  const SizedBox(height: Gaps.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GameButton(
                          label: 'Sync Now',
                          tone: ButtonTone.navy,
                          height: 42,
                          fontSize: 15,
                          onPressed: cloud.status == CloudStatus.syncing
                              ? null
                              : () => cloud.syncNow(),
                        ),
                      ),
                      const SizedBox(width: Gaps.sm),
                      Expanded(
                        child: GameButton(
                          label: 'Delete Cloud Data',
                          tone: ButtonTone.red,
                          height: 42,
                          fontSize: 15,
                          onPressed: () => _delete(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gaps.sm),
                  GameButton(
                    label: 'Sign Out',
                    tone: ButtonTone.navy,
                    height: 42,
                    fontSize: 15,
                    onPressed: cloud.status == CloudStatus.syncing
                        ? null
                        : () => _signOut(context),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _link(BuildContext context) async {
    final services = AppScope.of(context);
    try {
      final linked = await services.signInWithGoogle();
      if (linked) services.analytics.cloudLinked();
      if (context.mounted && linked) {
        showToast(context, 'Progress saved to your Google account.');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          e is CloudFailure
              ? e.message
              : 'Could not sign in. Check your connection and try again.',
          color: Palette.coral,
        );
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final services = AppScope.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message:
          'Your cloud save stays safe for your next sign-in. Until then, you '
          'play as a guest and new progress stays on this phone.',
      confirmLabel: 'Sign Out',
    );
    if (!ok || !context.mounted) return;
    try {
      await services.signOut();
      if (context.mounted) showToast(context, 'Signed out.');
    } catch (_) {
      if (context.mounted) {
        showToast(
          context,
          'Could not sign out. Try again.',
          color: Palette.coral,
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final services = AppScope.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Delete cloud data?',
      message:
          'This deletes your cloud save and account. Progress on this phone '
          'is kept. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    try {
      await services.deleteCloudData();
      if (context.mounted) showToast(context, 'Cloud data deleted.');
    } catch (_) {
      if (context.mounted) {
        showToast(
          context,
          'Could not delete. Check your connection and try again.',
          color: Palette.coral,
        );
      }
    }
  }
}

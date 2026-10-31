import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

enum LegalDoc { privacy, terms }

/// Offline copies of the privacy policy and terms, shown when the hosted
/// pages (website/) cannot be opened. Keep both in sync.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});
  final LegalDoc doc;

  /// Opens the hosted page, or the in-app copy if that is not possible.
  static Future<void> open(BuildContext context, LegalDoc doc) async {
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

  @override
  Widget build(BuildContext context) {
    final contact = AppConfig.supportEmail.isEmpty
        ? AppConfig.websiteUrl
        : AppConfig.supportEmail;
    final sections = doc == LegalDoc.privacy
        ? _privacy(contact)
        : _terms(contact);
    return ScreenShell(
      title: doc == LegalDoc.privacy ? 'Privacy Policy' : 'Terms of Service',
      showCoins: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.xl),
        children: [
          GamePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (heading, body) in sections) ...[
                  Text(
                    heading,
                    style: TextStyles.heading.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyles.caption.copyWith(
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: Gaps.md),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _privacy(String contact) => [
    (
      'Who we are',
      '${AppConfig.title} is a game by the ${AppConfig.title} team. Contact: $contact. Full policy: ${AppConfig.privacyPolicyUrl}',
    ),
    (
      'Data stored on your device',
      'Your progress (levels, stars, coins, upgrades, skins, scores, missions, daily reward dates) and settings are saved on this device. Uninstalling the app or using "Reset Progress" deletes them.',
    ),
    (
      'Cloud save and accounts',
      'You choose when you first open the game. As a guest there is no account and your progress stays on this device. If you choose "Continue with Google", your Google email address, name and account ID are stored with Google Firebase, with a copy of your progress in Google Cloud Firestore, so you can restore it on another phone.',
    ),
    (
      'Deleting your data',
      'Settings > Cloud Save > Delete Cloud Data deletes your cloud save and account immediately. You can also delete them on the web, without the app: ${AppConfig.deleteAccountUrl}',
    ),
    (
      'Analytics and crash reports',
      'With "Share Usage Data" on, Google Analytics for Firebase records how the game is used (screens opened, buttons tapped, sign-in choice, levels started and finished, power-ups and elements used, ads watched, items bought) with an app-instance ID, not your name or email. Firebase Crashlytics sends crash reports with technical device information. Turn it off any time in Settings.',
    ),
    (
      'Advertising',
      'The game may show optional ads from Google AdMob. Google may collect device identifiers (such as the advertising ID), IP address and ad interaction data to deliver, measure and, where you consent, personalise ads. Where required (for example in the EEA/UK), you are asked for consent first and can change it in Settings > Ad Privacy Choices. See https://policies.google.com/technologies/ads',
    ),
    (
      'Sharing and security',
      'We do not sell your data. Data is sent encrypted (HTTPS) and processed by Google as our service provider. Only you can read your cloud save.',
    ),
    (
      'Permissions',
      'The app uses internet access for cloud save, analytics and ads. It does not request location, contacts, camera, microphone or file access.',
    ),
    (
      'Children',
      'The game is intended for players aged 13 and over and does not knowingly collect data from younger children.',
    ),
    (
      'Changes',
      'We will update this policy if the app\'s data practices change. Last updated: 31 October 2026.',
    ),
  ];

  List<(String, String)> _terms(String contact) => [
    (
      'Using the game',
      '${AppConfig.title} is provided for personal entertainment. Coins and items have no real-world value and cannot be exchanged for money.',
    ),
    (
      'Purchases',
      'The game has no real-money purchases. All items are unlocked with in-game coins.',
    ),
    (
      'Progress',
      'Progress is stored on your device and, when cloud save is available, backed up to your account. Sign in with Google to keep it after reinstalling. Guest progress is only on your device, so we cannot restore it.',
    ),
    (
      'Ads',
      'Rewarded ads are optional. Rewards are granted only when the ad network confirms the ad was completed.',
    ),
    (
      'Fair play',
      'Do not cheat, modify the game or interfere with its services. We may reset progress obtained this way.',
    ),
    (
      'Liability',
      'The game is provided "as is" without warranties, to the extent permitted by law.',
    ),
    ('Contact', 'Questions: $contact. Full terms: ${AppConfig.termsUrl}'),
  ];
}

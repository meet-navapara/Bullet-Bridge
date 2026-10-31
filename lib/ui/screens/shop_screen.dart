import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/balance.dart';
import '../../economy/catalog.dart';
import '../../economy/upgrades.dart';
import '../../progress/player_progress.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _tab = 0;
  bool _busy = false;

  Future<void> _onItem({
    required String id,
    required String name,
    required int price,
    required bool owned,
    required bool selected,
    required bool isSkin,
    int? rewardChapter,
  }) async {
    if (_busy || selected) return;
    final services = AppScope.of(context);
    final progress = services.progress;
    if (!owned && rewardChapter != null) {
      showToast(
        context,
        'Defeat the chapter $rewardChapter boss to earn $name.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (owned) {
        isSkin ? await progress.selectSkin(id) : await progress.selectTheme(id);
        services.haptics.trigger(Haptic.selection);
        return;
      }
      if (progress.data.coins < price) {
        services.haptics.trigger(Haptic.heavy);
        if (mounted) {
          showToast(
            context,
            'Not enough coins for $name.',
            color: const Color(0xFF8A2433),
          );
        }
        return;
      }
      final ok = await confirmDialog(
        context,
        title: 'Buy $name?',
        message: 'Spend ${formatInt(price)} coins to unlock $name.',
        confirmLabel: 'Buy',
        confirmTone: ButtonTone.green,
      );
      if (!ok || !mounted) return;
      final result = isSkin
          ? await progress.buySkin(id)
          : await progress.buyTheme(id);
      if (!mounted) return;
      if (result == PurchaseResult.success) {
        services.analytics.itemBought(id);
        services.audio.play(Sfx.upgrade);
        services.haptics.trigger(Haptic.medium);
        showToast(
          context,
          '$name unlocked and equipped!',
          color: const Color(0xFF1E7A3E),
        );
      } else if (result == PurchaseResult.saveFailed) {
        showToast(
          context,
          'Could not save. Please try again.',
          color: const Color(0xFF8A2433),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchAdForCoins() async {
    final services = AppScope.of(context);
    final earned = await services.ads.showRewarded();
    services.analytics.rewardedAd('shop', earned: earned);
    if (!mounted) return;
    if (!earned) {
      showToast(context, 'Ad closed before the reward.');
      return;
    }
    final coins = await services.progress.grantAdCoins();
    if (!mounted) return;
    if (coins != null) {
      services.audio.play(Sfx.coin);
      showToast(context, '+$coins coins!', color: const Color(0xFF1E7A3E));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final progress = services.progress;
    return ScreenShell(
      title: 'Shop',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final data = progress.data;
          final cannonLevel = data.level(UpgradeType.cannonLevel);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
                child: _Tabs(
                  index: _tab,
                  labels: const ['Cannons', 'Themes'],
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: services.ads.rewardedReady,
                builder: (context, ready, _) {
                  if (!ready || !progress.canWatchAdForCoins) {
                    return const SizedBox(height: Gaps.md);
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gaps.lg,
                      Gaps.md,
                      Gaps.lg,
                      0,
                    ),
                    child: GameButton(
                      label: 'Free +${AdSpec.rewardedCoins} coins (watch ad)',
                      tone: ButtonTone.purple,
                      height: 46,
                      fontSize: 16,
                      icon: const Icon(
                        Icons.smart_display_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _watchAdForCoins,
                    ),
                  );
                },
              ),
              const SizedBox(height: Gaps.sm),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Gaps.lg,
                    Gaps.sm,
                    Gaps.lg,
                    Gaps.xl,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _tab == 0 ? 3 : 2,
                    mainAxisSpacing: Gaps.md,
                    crossAxisSpacing: Gaps.md,
                    childAspectRatio: _tab == 0 ? 0.74 : 0.8,
                  ),
                  itemCount: _tab == 0
                      ? Catalog.skins.length
                      : Catalog.themes.length,
                  itemBuilder: (context, i) {
                    if (_tab == 0) {
                      final skin = Catalog.skins[i];
                      final owned = data.ownedSkins.contains(skin.id);
                      final selected = data.selectedSkin == skin.id;
                      return _ShopCard(
                        name: skin.name,
                        price: skin.price,
                        owned: owned,
                        selected: selected,
                        affordable: data.coins >= skin.price,
                        rewardChapter: skin.rewardChapter,
                        preview: CannonPreview(
                          skin: skin,
                          level: cannonLevel,
                          size: 64,
                        ),
                        onTap: () => _onItem(
                          id: skin.id,
                          name: skin.name,
                          price: skin.price,
                          owned: owned,
                          selected: selected,
                          isSkin: true,
                          rewardChapter: skin.rewardChapter,
                        ),
                      );
                    }
                    final theme = Catalog.themes[i];
                    final owned = data.ownedThemes.contains(theme.id);
                    final selected = data.selectedTheme == theme.id;
                    return _ShopCard(
                      name: theme.name,
                      price: theme.price,
                      owned: owned,
                      selected: selected,
                      affordable: data.coins >= theme.price,
                      preview: ThemePreview(theme: theme),
                      onTap: () => _onItem(
                        id: theme.id,
                        name: theme.name,
                        price: theme.price,
                        owned: owned,
                        selected: selected,
                        isSkin: false,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Palette.panelInset,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.panelBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: i == index
                          ? const LinearGradient(
                              colors: [Color(0xFF4FA8FF), Color(0xFF2569F0)],
                            )
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyles.button.copyWith(
                        fontSize: 18,
                        color: i == index ? Colors.white : Palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.name,
    required this.price,
    required this.owned,
    required this.selected,
    required this.affordable,
    required this.preview,
    required this.onTap,
    this.rewardChapter,
  });

  final String name;

  /// Boss-reward items show where to earn them instead of a price.
  final int? rewardChapter;
  final int price;
  final bool owned;
  final bool selected;
  final bool affordable;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = selected ? 'Equipped' : (owned ? 'Owned' : 'Locked');
    return Semantics(
      button: true,
      label:
          '$name, $status${owned
              ? ''
              : rewardChapter != null
              ? ', boss reward of chapter $rewardChapter'
              : ', ${formatInt(price)} coins'}',
      child: GestureDetector(
        onTap: onTap,
        child: GamePanel(
          padding: const EdgeInsets.all(Gaps.sm),
          highlight: selected ? Palette.yellow : null,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: Opacity(
                          opacity: owned ? 1 : 0.75,
                          child: preview,
                        ),
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Palette.green,
                          size: 22,
                        ),
                      ),
                    if (!owned)
                      const Positioned(
                        left: 0,
                        top: 0,
                        child: Icon(
                          Icons.lock_rounded,
                          color: Palette.textMuted,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: TextStyles.caption.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Palette.yellow.withValues(alpha: 0.2)
                      : owned
                      ? Palette.blue.withValues(alpha: 0.35)
                      : Palette.panelInset,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: owned
                    ? Text(
                        selected ? 'Equipped' : 'Equip',
                        style: TextStyles.number.copyWith(
                          fontSize: 14,
                          color: selected ? Palette.yellow : Colors.white,
                        ),
                      )
                    : rewardChapter != null
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Boss Ch.$rewardChapter',
                          style: TextStyles.number.copyWith(
                            fontSize: 14,
                            color: Palette.yellow,
                          ),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CoinIcon(size: 16),
                            const SizedBox(width: 4),
                            Text(
                              formatInt(price),
                              style: TextStyles.number.copyWith(
                                fontSize: 14,
                                color: affordable
                                    ? Colors.white
                                    : Palette.coral,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

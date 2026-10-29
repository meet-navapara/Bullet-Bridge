import 'package:flutter/material.dart' hide Element;

import '../../app/app_services.dart';
import '../../economy/catalog.dart';
import '../../economy/upgrades.dart';
import '../../game/sim/entities.dart';
import '../../progress/player_progress.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});

  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  /// Upgrades with a purchase in flight; their buttons are disabled so a
  /// double tap can never send two transactions.
  final Set<UpgradeType> _pending = {};

  Future<void> _buy(UpgradeDef def, int level) async {
    if (_pending.contains(def.type)) return;
    setState(() => _pending.add(def.type));
    final services = AppScope.of(context);
    final result = await services.progress.purchaseUpgrade(def.type, level);
    if (!mounted) return;
    setState(() => _pending.remove(def.type));
    switch (result) {
      case PurchaseResult.success:
        services.analytics.upgradeBought(def.id, level + 1);
        services.audio.play(Sfx.upgrade);
        services.haptics.trigger(Haptic.medium);
        showToast(
          context,
          '${def.title} upgraded to Lv. ${level + 1}!',
          color: const Color(0xFF1E7A3E),
        );
      case PurchaseResult.insufficientFunds:
        services.haptics.trigger(Haptic.heavy);
        showToast(
          context,
          'Not enough coins. Play a run to earn more!',
          color: const Color(0xFF8A2433),
        );
      case PurchaseResult.maxed:
        showToast(context, '${def.title} is already maxed.');
      case PurchaseResult.saveFailed:
        showToast(
          context,
          'Could not save. Please try again.',
          color: const Color(0xFF8A2433),
        );
      case PurchaseResult.stale:
      case PurchaseResult.invalid:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ScreenShell(
      title: 'Upgrades',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final data = progress.data;
          final skin = Catalog.skin(data.selectedSkin);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Gaps.lg,
              Gaps.sm,
              Gaps.lg,
              Gaps.xl,
            ),
            itemCount: Upgrades.all.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gaps.md),
            itemBuilder: (context, i) {
              final def = Upgrades.all[i];
              final level = data.level(def.type);
              return _UpgradeCard(
                def: def,
                level: level,
                coins: data.coins,
                busy: _pending.contains(def.type),
                icon: _iconFor(
                  def.type,
                  skin,
                  data.level(UpgradeType.cannonLevel),
                ),
                onBuy: () => _buy(def, level),
              );
            },
          );
        },
      ),
    );
  }

  Widget _iconFor(UpgradeType type, CannonSkin skin, int cannonLevel) =>
      switch (type) {
        UpgradeType.fireRate => const Icon(
          Icons.fast_forward_rounded,
          color: Palette.purple,
          size: 38,
        ),
        UpgradeType.bulletPower => const Icon(
          Icons.bolt_rounded,
          color: Palette.cyan,
          size: 42,
        ),
        UpgradeType.cannonLevel => CannonPreview(
          skin: skin,
          level: cannonLevel,
          size: 46,
        ),
        UpgradeType.coinBonus => const CoinIcon(size: 38),
        UpgradeType.startingShield => const PowerUpIcon(
          type: PowerUpType.shield,
          size: 44,
        ),
        UpgradeType.elementPower => const ElementIcon(
          element: Element.fire,
          size: 40,
        ),
      };
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.def,
    required this.level,
    required this.coins,
    required this.busy,
    required this.icon,
    required this.onBuy,
  });

  final UpgradeDef def;
  final int level;
  final int coins;
  final bool busy;
  final Widget icon;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final cost = def.costToUpgrade(level);
    final maxed = cost == null;
    final affordable = !maxed && coins >= cost;
    final steps = def.maxLevel - def.minLevel;
    final filled = level - def.minLevel;
    return GamePanel(
      padding: const EdgeInsets.all(Gaps.md),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Palette.panelInset,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            alignment: Alignment.center,
            child: icon,
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        def.title,
                        style: TextStyles.heading.copyWith(fontSize: 18),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Lv. $level',
                      style: TextStyles.caption.copyWith(color: Palette.cyan),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  def.description,
                  style: TextStyles.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _Pips(filled: filled, total: steps),
                const SizedBox(height: 4),
                _ValueChange(
                  current: def.valueLabel(level),
                  next: maxed ? null : def.valueLabel(level + 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gaps.sm),
          SizedBox(
            width: 92,
            child: maxed
                ? Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Palette.panelInset,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'MAX',
                      style: TextStyles.button.copyWith(
                        fontSize: 18,
                        color: Palette.yellow,
                      ),
                    ),
                  )
                : GameButton(
                    label: formatCompactPrice(cost),
                    tone: affordable ? ButtonTone.green : ButtonTone.navy,
                    height: 44,
                    fontSize: 17,
                    icon: const CoinIcon(size: 18),
                    onPressed: busy ? null : onBuy,
                  ),
          ),
        ],
      ),
    );
  }
}

String formatCompactPrice(int value) =>
    value >= 100000 ? formatCompact(value) : formatInt(value);

class _Pips extends StatelessWidget {
  const _Pips({required this.filled, required this.total});
  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Long tracks are shown as a bar, short ones as segments.
    if (total > 10) {
      return ProgressBar(
        value: filled / total,
        color: Palette.green,
        height: 8,
      );
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 8,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < filled ? Palette.green : Palette.panelInset,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

/// "current -> next" with an icon arrow (the arrow glyph is not in every
/// font).
class _ValueChange extends StatelessWidget {
  const _ValueChange({required this.current, this.next});
  final String current;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final style = TextStyles.caption.copyWith(color: Colors.white);
    return Row(
      children: [
        Flexible(
          child: Text(current, style: style, overflow: TextOverflow.ellipsis),
        ),
        if (next != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: Palette.green,
            ),
          ),
          Flexible(
            child: Text(
              next!,
              style: style.copyWith(color: Palette.green),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

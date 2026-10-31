import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart' hide Element;

import '../../app/app_services.dart';
import '../../config/balance.dart';
import '../../config/campaign.dart';
import '../../economy/catalog.dart';
import '../../economy/upgrades.dart';
import '../../game/boomforge_game.dart';
import '../../game/hud_model.dart';
import '../../game/sim/entities.dart';
import '../../game/sim/game_simulation.dart';
import '../../game/sim/seeded_random.dart';
import '../../game/sim/wave_director.dart';
import '../../progress/daily.dart';
import '../../progress/player_progress.dart';
import '../../render/crystal_art.dart';
import '../../render/hud_art.dart';
import '../../render/icon_art.dart';
import '../../services/frame_monitor.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

enum _Overlay { none, paused, ended }

/// What a campaign level introduces, shown on its title card.
String stageHint(int stage) => Campaign.level(stage).hint;

String elementBlurb(Element e) => switch (e) {
  Element.kinetic => 'Solid all-rounder with full damage.',
  Element.fire => 'Splash damage. Double damage to rock armour.',
  Element.ice => 'Chills enemies; enough hits freeze them solid.',
  Element.electric => 'Every hit arcs to two nearby targets.',
};

/// Hosts one play session (any number of retries). Pass [stage] for a
/// campaign stage, [challenge] for today's daily challenge, or neither for
/// endless mode.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.stage, this.challenge});

  final int? stage;
  final DailyChallenge? challenge;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final HudModel _hud = HudModel();
  final FrameMonitor _frames = FrameMonitor();
  final _rng = math.Random();
  BoomforgeGame? _game;
  _Overlay _overlay = _Overlay.none;
  late final int? _stage = widget.stage;

  late String _runId;
  late DateTime _runStart;
  bool _committed = false;
  bool _committing = false;

  /// The last commit attempt could not be written. The level-clear card
  /// then offers "Retry Save" instead of moving on, because the next
  /// level only counts once this one is recorded.
  bool _saveFailed = false;
  bool _transitioning = false;

  /// A rewarded ad is on screen. It takes the app out of the foreground, but
  /// the run may still be revived, so it must not be committed yet.
  bool _showingAd = false;
  CommitOutcome? _outcome;
  int? _pointer;
  double _hintDrag = 0;
  bool _showDragHint = false;
  int _introKey = 0;

  AppServices get _services => AppScope.of(context);
  bool _servicesReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frames.start();
    _newRunId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servicesReady) {
      _servicesReady = true;
      final stage = _stage;
      if (stage != null) _services.analytics.levelStart(stage);
    }
    if (_game == null) _createGame();
  }

  Future<void> _createGame() async {
    final services = _services;
    final progress = services.progress;
    final data = progress.data;
    final challenge = widget.challenge;
    final stage = _stage;
    final bonus = challenge == null
        ? await progress.takeBonusPowerUps()
        : const <PowerUpType, int>{};
    if (!mounted) return;
    final RunPlan plan = stage != null ? StagePlan(stage) : const EndlessPlan();
    final game = BoomforgeGame(
      setup: RunSetup(
        loadout: challenge == null
            ? progress.loadout
            : Upgrades.dailyChallengeLoadout,
        plan: plan,
        seedFactory: switch ((stage, challenge)) {
          (final int s, _) => () => SeededRandom.hashString(
            'boomforge-stage-$s',
          ),
          (_, final DailyChallenge c) => () => c.seed,
          _ => () => _rng.nextInt(1 << 32),
        },
        startingPowerUps: bonus,
      ),
      skin: Catalog.skin(data.selectedSkin),
      // Every chapter after the first has its own environment; chapter 1,
      // Endless and the daily challenge use the player's chosen theme.
      theme: stage != null && StageSpec.chapterOf(stage) > 1
          ? Campaign.level(stage).chapterDef.theme
          : Catalog.theme(data.selectedTheme),
      audio: services.audio,
      haptics: services.haptics,
      hud: _hud,
      reducedMotion:
          data.settings.reducedMotion ||
          MediaQuery.of(context).disableAnimations,
      onRunEnded: _onRunEnded,
    );
    setState(() {
      _game = game;
      _showDragHint = data.stats.gamesPlayed < 2;
    });
  }

  void _newRunId() {
    _runId =
        '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(1 << 30)}';
    _runStart = DateTime.now();
    _committed = false;
    _outcome = null;
    final stage = _stage;
    // initState runs before the services are reachable; the first
    // level_start is logged from didChangeDependencies.
    if (stage != null && _servicesReady) _services.analytics.levelStart(stage);
    _introKey++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frames.stop();
    _hud.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (_overlay == _Overlay.none && !(_game?.isRunFinished ?? true)) {
      _pause();
    } else if (_overlay == _Overlay.ended && !_showingAd) {
      // Don't risk losing the run's coins if the app is killed now.
      _commit();
    }
  }

  // ------------------------------------------------------------- run flow

  bool get _canContinue {
    final sim = _game?.sim;
    return widget.challenge == null &&
        sim != null &&
        sim.isOver &&
        !sim.revived &&
        !_committed &&
        _services.ads.rewardedReady.value;
  }

  void _onRunEnded(GameSimulation sim) {
    if (!mounted) return;
    setState(() => _overlay = _Overlay.ended);
    _game?.pauseEngine();
    // Without a continue option, the result is final right away.
    if (!_canContinue) _commit();
  }

  Future<void> _commit() async {
    final sim = _game?.sim;
    if (sim == null || _committed || _committing) return;
    _committing = true;
    final outcome = await _services.progress.commitRun(
      RunResult(
        runId: _runId,
        score: sim.score,
        wave: sim.wave,
        wavesCleared: sim.wavesCleared,
        coins: sim.coins,
        ballsDestroyed: sim.ballsDestroyed,
        powerUpsUsed: sim.powerUpsUsed,
        challengeDate: widget.challenge?.date,
        stage: _stage,
        stageCleared: sim.isStageCleared,
        stars: sim.isStageCleared ? sim.stars : 0,
        bestChain: sim.bestChain,
      ),
    );
    _committing = false;
    if (!mounted) return;
    if (outcome.saveFailed) {
      // Leave the run uncommitted so the next commit point (retry, menu,
      // backgrounding) tries again instead of dropping its coins.
      showToast(
        context,
        'Could not save progress. Will retry.',
        color: Palette.coral,
      );
      setState(() => _saveFailed = true);
      return;
    }
    setState(() {
      _committed = true;
      _saveFailed = false;
      _outcome = outcome;
    });
    if (outcome.accepted) _logRunEnd(sim, outcome);
  }

  void _logRunEnd(GameSimulation sim, CommitOutcome outcome) {
    final analytics = _services.analytics;
    final stage = _stage;
    if (stage == null) {
      if (widget.challenge == null) {
        analytics.endlessEnd(wave: sim.wave, score: sim.score);
      }
      return;
    }
    analytics.levelEnd(
      level: stage,
      cleared: sim.isStageCleared,
      stars: sim.isStageCleared ? sim.stars : 0,
      seconds: sim.elapsed.round(),
      score: sim.score,
    );
    final boss = sim.boss;
    if (sim.bossDefeated && boss != null) {
      analytics.bossDefeated(stage, boss.def.name);
    }
    final chapter = outcome.chapterCompleted;
    if (chapter != null) analytics.chapterComplete(chapter);
  }

  Future<void> _continueWithAd() async {
    _showingAd = true;
    final bool earned;
    try {
      earned = await _services.ads.showRewarded();
    } finally {
      _showingAd = false;
    }
    if (!mounted) return;
    _services.analytics.rewardedAd('continue', earned: earned);
    if (earned && _game!.revive()) {
      _game!.resumeEngine();
      setState(() => _overlay = _Overlay.none);
    } else {
      showToast(context, 'No reward this time.');
      _commit();
    }
  }

  /// Ends the current run (committing it) and offers an interstitial at
  /// this natural break.
  Future<void> _finishRun() async {
    await _commit();
    if (!mounted) return;
    final services = _services;
    final shown = await services.ads.maybeShowInterstitial(
      gamesSinceLast: services.progress.data.gamesSinceInterstitial,
      lastRunLength: DateTime.now().difference(_runStart),
    );
    if (shown) {
      services.analytics.interstitialShown();
      await services.progress.markInterstitialShown();
    }
  }

  Future<void> _restart({int? stage}) async {
    if (_transitioning) return;
    _transitioning = true;
    await _finishRun();
    _transitioning = false;
    if (!mounted) return;
    if (stage != null && stage != _stage) {
      // A different stage needs a different plan: rebuild the game.
      Navigator.of(context)
          .pushReplacement(gameRoute<void>(GameScreen(stage: stage)));
      return;
    }
    _newRunId();
    _game!
      ..startRun()
      ..resumeEngine();
    setState(() => _overlay = _Overlay.none);
  }

  Future<void> _exitToMenu() async {
    if (_transitioning) return;
    _transitioning = true;
    await _finishRun();
    if (mounted) Navigator.of(context).pop();
  }

  void _pause() {
    final game = _game;
    if (game == null || _overlay != _Overlay.none) return;
    game.pauseEngine();
    setState(() => _overlay = _Overlay.paused);
  }

  void _resume() {
    _game?.resumeEngine();
    setState(() => _overlay = _Overlay.none);
  }

  Future<void> _confirmRestartFromPause() async {
    final ok = await confirmDialog(
      context,
      title: 'Restart?',
      message: 'This run ends now. Coins collected so far are kept.',
      confirmLabel: 'Restart',
      confirmTone: ButtonTone.yellow,
    );
    if (ok) await _restart();
  }

  Future<void> _confirmQuitFromPause() async {
    final ok = await confirmDialog(
      context,
      title: 'Leave run?',
      message: 'This run ends now. Coins collected so far are kept.',
      confirmLabel: 'Leave',
    );
    if (ok) await _exitToMenu();
  }

  // ---------------------------------------------------------------- input

  void _onPointerDown(PointerDownEvent e) => _pointer ??= e.pointer;

  void _onPointerMove(PointerMoveEvent e) {
    // If the steering finger lifted while another stayed down (a second
    // finger or the palm), the finger still moving takes over; otherwise
    // the cannon would ignore the player until they touched again.
    _pointer ??= e.pointer;
    if (e.pointer != _pointer || _overlay != _Overlay.none) return;
    _game?.dragBy(e.delta.dx);
    if (_showDragHint) {
      _hintDrag += e.delta.dx.abs();
      if (_hintDrag > 80) setState(() => _showDragHint = false);
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final stage = _stage;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_overlay) {
          case _Overlay.none:
            _pause();
          case _Overlay.paused:
            _resume();
          case _Overlay.ended:
            _exitToMenu();
        }
      },
      child: Scaffold(
        backgroundColor: Palette.background,
        body: game == null
            ? const SizedBox.expand()
            : Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerUp,
                      // The game repaints every frame; keep it in its own
                      // layer so the HUD widgets are not repainted with it.
                      child: RepaintBoundary(child: GameWidget(game: game)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SafeArea(
                      bottom: false,
                      child: RepaintBoundary(
                        child: _TopHud(
                          hud: _hud,
                          onPause: _pause,
                          stage: stage,
                          challenge: widget.challenge,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomBar(
                      hud: _hud,
                      onElement: (e) {
                        _services.analytics.elementSelected(e.name);
                        _game?.selectElement(e);
                      },
                      onPowerUp: (t) {
                        _services.analytics.powerUpUsed(t.name);
                        _game?.activatePowerUp(t);
                      },
                    ),
                  ),
                  if (_showDragHint && _overlay == _Overlay.none)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 150,
                      child: IgnorePointer(child: _DragHint()),
                    ),
                  if (stage != null && _overlay == _Overlay.none)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _StageIntro(
                          key: ValueKey(_introKey),
                          stage: stage,
                        ),
                      ),
                    ),
                  if (_overlay != _Overlay.none)
                    Positioned.fill(
                      // Overlays sit outside the Scaffold body's Material
                      // ink, so give them their own for text and ink.
                      child: Material(
                        type: MaterialType.transparency,
                        child: _buildOverlay(),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildOverlay() {
    if (_overlay == _Overlay.paused) {
      return _PauseOverlay(
        onResume: _resume,
        onRestart: _confirmRestartFromPause,
        onMenu: _confirmQuitFromPause,
      );
    }
    final sim = _game!.sim!;
    if (sim.isStageCleared) {
      final stage = _stage!;
      return _StageClearOverlay(
        sim: sim,
        stage: stage,
        outcome: _outcome,
        hasNext: stage < StageSpec.levelCount,
        // The next level opens only once this clear is saved.
        onNext: stage < StageSpec.levelCount && _committed
            ? () => _restart(stage: stage + 1)
            : null,
        onRetrySave: _saveFailed && !_committing ? _commit : null,
        onReplay: _restart,
        onMenu: _exitToMenu,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _services.ads.rewardedReady,
      builder: (context, _, _) => _GameOverOverlay(
        sim: sim,
        stage: _stage,
        outcome: _outcome,
        challenge: widget.challenge,
        canContinue: _canContinue,
        onContinue: _continueWithAd,
        onRestart: _restart,
        onMenu: _exitToMenu,
      ),
    );
  }
}

// ---------------------------------------------------------------- HUD

class _TopHud extends StatelessWidget {
  const _TopHud({
    required this.hud,
    required this.onPause,
    this.stage,
    this.challenge,
  });
  final HudModel hud;
  final VoidCallback onPause;
  final int? stage;
  final DailyChallenge? challenge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, 0),
      child: ListenableBuilder(
        listenable: hud,
        builder: (context, _) {
          final label = stage != null
              ? 'LEVEL $stage'
              : (challenge != null ? 'DAILY' : 'ENDLESS');
          final total = hud.waveCount;
          final waveText = total == null
              ? 'Wave ${hud.wave}'
              : 'Wave ${math.min(hud.wave, total)}/$total';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shrinks only when a big score, big coin count and large
                  // system text leave it no room on a narrow phone.
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HudChip(
                              icon: _ScoreBadge(label: label),
                              child: Text(
                                formatInt(hud.score),
                                style: TextStyles.number.copyWith(fontSize: 18),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 6),
                                for (var i = 0; i < hud.maxHull; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: HeartIcon(
                                      filled: i < hud.hull,
                                      size: 22,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  waveText,
                                  style: TextStyles.number.copyWith(
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  HudChip(
                    icon: const CoinIcon(size: 32),
                    child: Text(
                      formatInt(hud.coins),
                      style: TextStyles.number.copyWith(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: Gaps.sm),
                  RoundIconButton(
                    icon: Icons.pause_rounded,
                    tooltip: 'Pause',
                    size: 42,
                    onPressed: onPause,
                  ),
                ],
              ),
              if (challenge != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Daily: ${challenge!.title}',
                    textAlign: TextAlign.center,
                    style: TextStyles.number.copyWith(
                      fontSize: 15,
                      color: Palette.yellow,
                    ),
                  ),
                ),
              if (hud.bossFraction != null) ...[
                const SizedBox(height: Gaps.sm),
                _BossBar(
                  name: hud.bossName,
                  fraction: hud.bossFraction!,
                  phase: hud.bossPhase,
                  phases: hud.bossPhases,
                  ballsLeft: hud.bossBallsLeft,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF203152),
        border: Border.all(color: Palette.outline, width: 2.5),
      ),
      alignment: Alignment.center,
      child: Semantics(
        label: label,
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: Palette.yellow,
          size: 22,
        ),
      ),
    );
  }
}

class _BossBar extends StatelessWidget {
  const _BossBar({
    required this.name,
    required this.fraction,
    required this.phase,
    required this.phases,
    required this.ballsLeft,
  });
  final String name;
  final double fraction;
  final int phase;
  final int phases;
  final int ballsLeft;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '$name health ${(fraction * 100).round()} percent, '
          'phase $phase of $phases',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.number.copyWith(fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              for (var i = 1; i <= phases; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= phase ? Palette.coral : const Color(0x55FFFFFF),
                    border: Border.all(color: Palette.outline, width: 1.5),
                  ),
                ),
              if (ballsLeft > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.circle, size: 16, color: Palette.cyan),
                Text(
                  'x$ballsLeft',
                  style: TextStyles.number.copyWith(fontSize: 13),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          ProgressBar(value: fraction, color: Palette.coral, height: 12),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.hud,
    required this.onElement,
    required this.onPowerUp,
  });
  final HudModel hud;
  final void Function(Element) onElement;
  final void Function(PowerUpType) onPowerUp;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.sm, 0, Gaps.sm, Gaps.sm),
        child: ListenableBuilder(
          listenable: hud,
          builder: (context, _) => Row(
            children: [
              for (final e in Element.values)
                Expanded(
                  child: _ElementButton(
                    element: e,
                    selected: hud.element == e,
                    unlocked: hud.elements.contains(e),
                    onTap: () => onElement(e),
                  ),
                ),
              Container(
                width: 3,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: const Color(0x551C1830),
              ),
              for (final type in PowerUpType.values)
                Expanded(
                  child: _PowerUpButton(
                    type: type,
                    count: hud.inventory[type] ?? 0,
                    available: hud.available[type] ?? false,
                    active: hud.activeFraction[type] ?? 0,
                    onTap: () => onPowerUp(type),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElementButton extends StatelessWidget {
  const _ElementButton({
    required this.element,
    required this.selected,
    required this.unlocked,
    required this.onTap,
  });
  final Element element;
  final bool selected;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = elementColor(element);
    final name = HudArt.elementName(element);
    return Semantics(
      button: true,
      selected: selected,
      enabled: unlocked,
      label: unlocked
          ? '$name element${selected ? ', selected' : ''}'
          : '$name element, locked until level ${Upgrades.unlockStage(element)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: unlocked ? onTap : null,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.12 : 0.92,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked
                    ? (selected
                          ? Color.lerp(color, Colors.black, 0.35)
                          : const Color(0xFF203152))
                    : const Color(0xFF3A4060),
                border: Border.all(
                  color: selected ? Colors.white : Palette.outline,
                  width: selected ? 3 : 2.5,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x55000000),
                    offset: Offset(0, 3),
                  ),
                  if (selected)
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 12,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: unlocked
                  ? ElementIcon(element: element, size: 28)
                  : const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF9AA3C4),
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerUpButton extends StatelessWidget {
  const _PowerUpButton({
    required this.type,
    required this.count,
    required this.available,
    required this.active,
    required this.onTap,
  });

  final PowerUpType type;
  final int count;
  final bool available;
  final double active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = IconArt.colorFor(type);
    final isActive = active > 0;
    return Semantics(
      button: true,
      enabled: available,
      label:
          '${IconArt.labelFor(type)}, $count left${isActive ? ', active' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: available ? onTap : null,
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF203152),
                      border: Border.all(
                        color: isActive ? color : Palette.outline,
                        width: isActive ? 3 : 2.5,
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x55000000),
                          offset: Offset(0, 3),
                        ),
                        if (isActive)
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 10,
                          ),
                      ],
                    ),
                  ),
                ),
                if (isActive)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: CircularProgressIndicator(
                        value: active,
                        strokeWidth: 3,
                        color: color,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                Center(
                  child: Opacity(
                    opacity: count > 0 || isActive ? 1 : 0.35,
                    child: PowerUpIcon(type: type, size: 32),
                  ),
                ),
                Positioned(
                  right: -5,
                  bottom: -5,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: count > 0
                          ? Palette.coral
                          : const Color(0xFF3A4060),
                      shape: BoxShape.circle,
                      border: Border.all(color: Palette.outline, width: 2),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyles.number.copyWith(
                        fontSize: 11,
                        shadows: const [],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHint extends StatefulWidget {
  const _DragHint();

  @override
  State<_DragHint> createState() => _DragHintState();
}

class _DragHintState extends State<_DragHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('SWIPE TO MOVE', style: TextStyles.title.copyWith(fontSize: 24)),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              (Curves.easeInOut.transform(_c.value) - 0.5) * 140,
              0,
            ),
            child: child,
          ),
          child: const Icon(
            Icons.touch_app_rounded,
            color: Colors.white,
            size: 52,
            shadows: [
              Shadow(
                color: Palette.outline,
                offset: Offset(0, 3),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big "LEVEL n" title card at the start of a stage, then fades away.
class _StageIntro extends StatefulWidget {
  const _StageIntro({super.key, required this.stage});
  final int stage;

  @override
  State<_StageIntro> createState() => _StageIntroState();
}

class _StageIntroState extends State<_StageIntro>
    with SingleTickerProviderStateMixin {
  late final LevelDef _level = Campaign.level(widget.stage);

  /// Chapter openers and bosses hold their card a little longer.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: _level.slot == 1 || _level.isBoss ? 3400 : 2600,
    ),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = _level;
    final boss = level.isBoss;
    final chapter = level.chapterDef;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (t >= 1) return const SizedBox.shrink();
        final appear = Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0));
        final fade = 1 - ((t - 0.78) / 0.22).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Align(
            alignment: const Alignment(0, -0.3),
            child: Transform.scale(
              scale: 0.5 + 0.5 * appear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (level.slot == 1)
                      Text(
                        'CHAPTER ${chapter.number}',
                        style: TextStyles.title.copyWith(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    Text(
                      chapter.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyles.title.copyWith(
                        fontSize: 22,
                        color: Palette.yellow,
                      ),
                    ),
                    _BigLevelText(
                      text: boss ? 'BOSS' : 'LEVEL ${widget.stage}',
                      boss: boss,
                    ),
                    if (boss)
                      Text(
                        level.boss!.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyles.title.copyWith(
                          fontSize: 24,
                          color: Palette.coral,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      stageHint(widget.stage),
                      textAlign: TextAlign.center,
                      style: TextStyles.heading.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      level.animation.label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyles.caption.copyWith(
                        color: Colors.white,
                        shadows: TextStyles.outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Italic blue lettering with a yellow rim, the stage title style.
class _BigLevelText extends StatelessWidget {
  const _BigLevelText({required this.text, this.boss = false});
  final String text;
  final bool boss;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: TextStyles.display,
      fontSize: 64,
      height: 1.05,
    );
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(-0.12),
      child: Stack(
        children: [
          Text(
            text,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 16
                ..strokeJoin = StrokeJoin.round
                ..color = Palette.outline,
            ),
          ),
          Text(
            text,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 8
                ..strokeJoin = StrokeJoin.round
                ..color = Palette.yellow,
            ),
          ),
          ShaderMask(
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: boss
                  ? const [Color(0xFFFFA0A0), Color(0xFFE5243B)]
                  : const [Color(0xFF5AB2FF), Color(0xFF1336D6)],
            ).createShader(r),
            child: Text(text, style: style.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ overlays

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ColoredBox(
        color: Color.fromRGBO(10, 14, 40, 0.6 * t),
        child: Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onMenu,
  });
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return _Scrim(
      child: GamePanel(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Paused', style: TextStyles.title.copyWith(fontSize: 36)),
            const SizedBox(height: Gaps.lg),
            GameButton(
              label: 'Resume',
              tone: ButtonTone.green,
              onPressed: onResume,
            ),
            const SizedBox(height: Gaps.md),
            GameButton(
              label: 'Restart',
              tone: ButtonTone.yellow,
              onPressed: onRestart,
            ),
            const SizedBox(height: Gaps.lg),
            ListenableBuilder(
              listenable: progress,
              builder: (context, _) {
                final s = progress.data.settings;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QuickToggle(
                      icon: s.music
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      label: 'Music',
                      on: s.music,
                      onTap: () =>
                          progress.updateSettings((x) => x.music = !x.music),
                    ),
                    _QuickToggle(
                      icon: s.sfx
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: 'Sound',
                      on: s.sfx,
                      onTap: () =>
                          progress.updateSettings((x) => x.sfx = !x.sfx),
                    ),
                    _QuickToggle(
                      icon: s.vibration
                          ? Icons.vibration_rounded
                          : Icons.mobile_off_rounded,
                      label: 'Vibration',
                      on: s.vibration,
                      onTap: () => progress.updateSettings(
                        (x) => x.vibration = !x.vibration,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Gaps.lg),
            GameButton(
              label: 'Leave Run',
              tone: ButtonTone.navy,
              height: 50,
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: on,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: on ? Palette.blue : const Color(0xFF3A4060),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.outline, width: 3),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyles.caption.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count of 3 stars',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 350 + i * 250),
              curve: Curves.elasticOut,
              builder: (context, t, child) =>
                  Transform.scale(scale: i < count ? t : 1, child: child),
              child: Padding(
                padding: EdgeInsets.only(bottom: i == 1 ? 14 : 0),
                child: Icon(
                  Icons.star_rounded,
                  size: i == 1 ? 76 : 60,
                  color: i < count ? Palette.yellow : const Color(0x553A4060),
                  shadows: const [
                    Shadow(color: Palette.outline, offset: Offset(0, 3)),
                    Shadow(color: Palette.outline, offset: Offset(2, 0)),
                    Shadow(color: Palette.outline, offset: Offset(-2, 0)),
                    Shadow(color: Palette.outline, offset: Offset(0, -2)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StageClearOverlay extends StatelessWidget {
  const _StageClearOverlay({
    required this.sim,
    required this.stage,
    required this.outcome,
    required this.hasNext,
    required this.onNext,
    required this.onRetrySave,
    required this.onReplay,
    required this.onMenu,
  });

  final GameSimulation sim;
  final int stage;
  final CommitOutcome? outcome;
  final bool hasNext;

  /// Null until the clear has been saved.
  final VoidCallback? onNext;

  /// Set when saving failed; replaces the next-level button.
  final VoidCallback? onRetrySave;
  final VoidCallback onReplay;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    final unlocked = o?.unlocked;
    final level = Campaign.level(stage);
    final boss = level.boss;
    final campaignDone = stage == StageSpec.levelCount;
    final chapterDone = o?.chapterCompleted;
    final skinId = o?.rewardSkin;
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BigLevelText(
            text: campaignDone
                ? 'VICTORY!'
                : boss != null
                ? 'BOSS DOWN!'
                : 'CLEAR!',
          ),
          const SizedBox(height: Gaps.sm),
          _Stars(count: sim.stars),
          const SizedBox(height: Gaps.md),
          GamePanel(
            wood: true,
            padding: const EdgeInsets.symmetric(
              horizontal: Gaps.xl,
              vertical: Gaps.lg,
            ),
            child: Column(
              children: [
                Text(
                  boss != null
                      ? 'The ${boss.name} is shattered!'
                      : 'Level $stage complete',
                  style: TextStyles.heading.copyWith(fontSize: 19),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gaps.md),
                _RewardRow(label: 'Score', value: formatInt(sim.score)),
                _RewardRow(
                  label: 'Coins collected',
                  value: formatInt(sim.coins),
                  coin: true,
                ),
                if (o != null && o.stageBonus > 0)
                  _RewardRow(
                    label: o.firstClear
                        ? 'First clear bonus (x2)'
                        : 'Replay bonus',
                    value: '+${formatInt(o.stageBonus)}',
                    coin: true,
                  ),
                if (o != null && o.bossReward > 0)
                  _RewardRow(
                    label: 'Chapter reward',
                    value: '+${formatInt(o.bossReward)}',
                    coin: true,
                  ),
                if (sim.bestChain >= 2)
                  _RewardRow(label: 'Best chain', value: 'x${sim.bestChain}'),
                if (o == null)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
              ],
            ),
          ),
          if (unlocked != null) ...[
            const SizedBox(height: Gaps.md),
            GamePanel(
              highlight: elementColor(unlocked),
              padding: const EdgeInsets.all(Gaps.md),
              child: Row(
                children: [
                  ElementIcon(element: unlocked, size: 48),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW ELEMENT: ${HudArt.elementName(unlocked).toUpperCase()}',
                          style: TextStyles.heading.copyWith(
                            fontSize: 17,
                            color: elementColor(unlocked),
                          ),
                        ),
                        Text(
                          elementBlurb(unlocked),
                          style: TextStyles.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (chapterDone != null) ...[
            const SizedBox(height: Gaps.md),
            GamePanel(
              highlight: Palette.yellow,
              padding: const EdgeInsets.all(Gaps.md),
              child: Row(
                children: [
                  if (skinId != null)
                    CannonPreview(skin: Catalog.skin(skinId), size: 52)
                  else
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Palette.yellow,
                      size: 48,
                    ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaignDone
                              ? 'CAMPAIGN COMPLETE!'
                              : 'CHAPTER $chapterDone COMPLETE!',
                          style: TextStyles.heading.copyWith(
                            fontSize: 17,
                            color: Palette.yellow,
                          ),
                        ),
                        Text(
                          skinId != null
                              ? 'New cannon skin: ${Catalog.skin(skinId).name}'
                              : campaignDone
                              ? 'You broke the world. Thanks for playing!'
                              : 'Next: ${Campaign.chapter(chapterDone + 1).name}',
                          style: TextStyles.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gaps.lg),
          if (onRetrySave != null) ...[
            GameButton(
              label: 'Retry Save',
              tone: ButtonTone.red,
              onPressed: onRetrySave,
            ),
            const SizedBox(height: Gaps.sm),
          ] else if (hasNext) ...[
            GameButton(
              label: boss != null ? 'Next Chapter' : 'Next Level',
              tone: ButtonTone.green,
              onPressed: onNext,
            ),
            const SizedBox(height: Gaps.sm),
          ],
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: 'Replay',
                  tone: ButtonTone.yellow,
                  height: 50,
                  onPressed: onReplay,
                ),
              ),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: GameButton(
                  label: 'Menu',
                  tone: ButtonTone.navy,
                  height: 50,
                  onPressed: onMenu,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.label,
    required this.value,
    this.coin = false,
  });
  final String label;
  final String value;
  final bool coin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyles.body.copyWith(shadows: TextStyles.outlined),
            ),
          ),
          if (coin) ...[const CoinIcon(size: 20), const SizedBox(width: 4)],
          Text(value, style: TextStyles.number.copyWith(fontSize: 20)),
        ],
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.sim,
    required this.stage,
    required this.outcome,
    required this.challenge,
    required this.canContinue,
    required this.onContinue,
    required this.onRestart,
    required this.onMenu,
  });

  final GameSimulation sim;
  final int? stage;
  final CommitOutcome? outcome;
  final DailyChallenge? challenge;
  final bool canContinue;
  final VoidCallback onContinue;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).progress.data;
    final best = math.max(data.bestScore, sim.score);
    final newBest = outcome?.newBestScore ?? false;
    final challengeReward = outcome?.challengeReward ?? 0;
    final c = challenge;
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BigLevelText(text: 'DEFEATED', boss: true),
          const SizedBox(height: Gaps.md),
          GamePanel(
            wood: true,
            padding: const EdgeInsets.symmetric(
              horizontal: Gaps.xl,
              vertical: Gaps.lg,
            ),
            child: Column(
              children: [
                if (stage != null)
                  Text(
                    'Level $stage · wave ${sim.wave}/${sim.plan.waveCount}',
                    style: TextStyles.heading.copyWith(fontSize: 18),
                  ),
                _RewardRow(label: 'Score', value: formatInt(sim.score)),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    newBest ? 'NEW BEST!' : 'Best: ${formatInt(best)}',
                    style: TextStyles.caption.copyWith(
                      color: newBest ? Palette.yellow : Colors.white,
                      shadows: TextStyles.outlined,
                    ),
                  ),
                ),
                if (stage == null)
                  _RewardRow(label: 'Wave reached', value: '${sim.wave}'),
                _RewardRow(
                  label: 'Coins earned (kept)',
                  value: formatInt(sim.coins + challengeReward),
                  coin: true,
                ),
                if (sim.bestChain >= 2)
                  _RewardRow(label: 'Best chain', value: 'x${sim.bestChain}'),
                if (c != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      challengeReward > 0
                          ? 'Challenge complete! +$challengeReward coins'
                          : '${c.title}: ${c.progressFrom(wave: sim.wave, ballsDestroyed: sim.ballsDestroyed, score: sim.score)}/${c.target}',
                      style: TextStyles.body.copyWith(
                        color: challengeReward > 0
                            ? Palette.green
                            : Colors.white,
                        shadows: TextStyles.outlined,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gaps.lg),
          if (canContinue) ...[
            GameButton(
              label: 'Continue',
              tone: ButtonTone.green,
              icon: const Icon(
                Icons.smart_display_rounded,
                color: Colors.white,
              ),
              onPressed: onContinue,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: Gaps.sm),
              child: Text(
                'Watch an ad to revive once',
                style: TextStyles.caption.copyWith(
                  color: Colors.white,
                  shadows: TextStyles.outlined,
                ),
              ),
            ),
          ],
          GameButton(label: 'Retry', onPressed: onRestart),
          const SizedBox(height: Gaps.sm),
          GameButton(
            label: 'Menu',
            tone: ButtonTone.navy,
            height: 50,
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

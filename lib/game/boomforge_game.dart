import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import '../config/balance.dart';
import '../economy/catalog.dart';
import '../render/ball_art.dart';
import '../render/cannon_art.dart';
import '../render/crystal_art.dart';
import '../render/icon_art.dart';
import '../render/world_art.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import '../ui/theme/palette.dart';
import 'effects.dart';
import 'hud_model.dart';
import '../config/bosses.dart';
import 'sim/boss.dart';
import 'sim/entities.dart';
import 'sim/game_simulation.dart';
import 'sim/wave_director.dart';

/// Everything needed to start (or restart) a run.
class RunSetup {
  const RunSetup({
    required this.loadout,
    required this.seedFactory,
    this.plan = const EndlessPlan(),
    this.startingPowerUps = const {},
    this.startElement = Element.kinetic,
  });

  final Loadout loadout;

  /// Called for each new run; stages and the daily challenge use fixed seeds.
  final int Function() seedFactory;
  final RunPlan plan;
  final Map<PowerUpType, int> startingPowerUps;
  final Element startElement;
}

/// Flame game: runs the fixed-step [GameSimulation], renders the world and
/// turns simulation events into effects, sound and haptics.
class BoomforgeGame extends FlameGame {
  BoomforgeGame({
    required this.setup,
    required this.skin,
    required this.theme,
    required this.audio,
    required this.haptics,
    required this.hud,
    required this.onRunEnded,
    bool reducedMotion = false,
  }) : effects = EffectsLayer(reducedMotion: reducedMotion),
       _bonusPowerUps = setup.startingPowerUps;

  final RunSetup setup;
  final CannonSkin skin;
  final ArenaTheme theme;
  final AudioService audio;
  final HapticsService haptics;
  final HudModel hud;

  /// Called once per run when it ends (game over or stage cleared), after
  /// the finishing effects have played.
  final void Function(GameSimulation sim) onRunEnded;
  final EffectsLayer effects;

  Map<PowerUpType, int> _bonusPowerUps;
  GameSimulation? _sim;
  GameSimulation? get sim => _sim;

  final CrystalArt _art = CrystalArt();
  CrystalArt get art => _art;
  final Map<WorldLayer, _Baked> _layers = {};
  _Baked? _ground;
  Size _layoutSize = Size.zero;

  // Viewport mapping from world units to pixels.
  double _scale = 1;
  Offset _origin = Offset.zero;
  double _arenaHeight = Physics.minArenaHeight;

  double _recoil = 0;
  double _muzzle = 0;
  double _tilt = 0;
  double _wheel = 0;
  double _lastCannonX = 0;
  double _time = 0;
  double _endDelay = -1;
  bool _endReported = false;

  final Paint _paint = Paint();
  final Paint _shieldPaint = Paint();

  bool get isRunFinished => _sim?.isFinished ?? false;

  @override
  Color backgroundColor() => theme.skyBottom;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _layout(Size(size.x, size.y));
    if (_sim == null && size.x > 0 && size.y > 0) startRun();
  }

  void _layout(Size screen) {
    if (screen.isEmpty) return;
    final widthScale = screen.width / Physics.worldWidth;
    final arenaH = (screen.height / widthScale).clamp(
      Physics.minArenaHeight,
      Physics.maxArenaHeight,
    );
    _arenaHeight = arenaH;
    _scale = math.min(widthScale, screen.height / arenaH);
    // Centre horizontally, anchor the ground to the bottom of the screen.
    _origin = Offset(
      (screen.width - Physics.worldWidth * _scale) / 2,
      screen.height - arenaH * _scale,
    );
    final dpr = _devicePixelRatio;
    _art.pixelRatio = _scale * dpr;
    if (_layoutSize == screen) return;
    _layoutSize = screen;
    final groundTop = _origin.dy + (arenaH - Physics.floorHeight) * _scale;
    // The backdrop is static, so each layer is rasterised once. Replaying
    // the vector pictures every frame (blurs, hundreds of paths) was the
    // main per-frame cost on phones.
    final layerRect = Rect.fromLTRB(
      -screen.width * WorldArt.overscan,
      0,
      screen.width * (1 + WorldArt.overscan),
      screen.height,
    );
    final detail = math.min(dpr, 2.0);
    for (final layer in WorldLayer.values) {
      _layers[layer]?.dispose();
      _layers[layer] = _Baked.paint(
        layerRect,
        // The sky is smooth gradients, so it can be stored at low res.
        layer == WorldLayer.sky ? math.min(dpr, 1.0) : detail,
        (c) => WorldArt.paintLayer(c, layer, screen, groundTop, theme),
      );
    }
    final groundRect = Rect.fromLTRB(
      -20,
      groundTop - 12,
      screen.width + 20,
      screen.height + 20,
    );
    _ground?.dispose();
    _ground = _Baked.paint(
      groundRect,
      detail,
      (c) => WorldArt.paintGround(
        c,
        Rect.fromLTRB(-20, groundTop, screen.width + 20, screen.height + 20),
        theme,
      ),
    );
  }

  static double get _devicePixelRatio {
    final views = PlatformDispatcher.instance.views;
    return views.isEmpty ? 2 : views.first.devicePixelRatio;
  }

  /// Starts a fresh run, discarding any previous state.
  void startRun() {
    final sim = GameSimulation(
      loadout: setup.loadout,
      seed: setup.seedFactory(),
      arenaHeight: size.y > 0 ? _arenaHeight : Physics.minArenaHeight,
      startingPowerUps: _bonusPowerUps,
      plan: setup.plan,
    )..setElement(setup.startElement);
    // One-off bonuses (daily reward) apply to the first run only.
    _bonusPowerUps = const {};
    _sim = sim;
    effects.clear();
    _endDelay = -1;
    _endReported = false;
    _recoil = 0;
    _tilt = 0;
    _lastCannonX = sim.cannonX;
    // Cached across restarts, so this only costs time on the first run.
    _art.prewarm(BallSpec.radius, BallArt.colorForTier);
    // The HUD is synced on the next update(); syncing here could notify
    // listeners while Flutter is still laying out the GameWidget.
  }

  /// Horizontal finger movement in logical pixels.
  void dragBy(double dxPixels) {
    final sim = _sim;
    if (sim == null || paused) return;
    sim.moveCannonBy(dxPixels / _scale * CannonSpec.dragSensitivity);
  }

  bool selectElement(Element e) {
    final sim = _sim;
    if (sim == null || paused || sim.element == e) return false;
    final ok = sim.setElement(e);
    if (ok) {
      effects.ring(
        sim.cannonX,
        sim.floorY - 30,
        40,
        elementColor(e),
        life: 0.35,
      );
      audio.play(Sfx.click);
      hud.sync(sim);
    }
    return ok;
  }

  bool activatePowerUp(PowerUpType type) {
    final sim = _sim;
    if (sim == null || paused) return false;
    final ok = sim.activatePowerUp(type);
    if (ok) _drainEvents(sim);
    hud.sync(sim);
    return ok;
  }

  /// Continue after a rewarded ad.
  bool revive() {
    final sim = _sim;
    if (sim == null || !sim.revive()) return false;
    _endDelay = -1;
    _endReported = false;
    effects.ring(sim.cannonX, sim.floorY - 25, 140, Palette.cyan, life: 0.7);
    effects.showBanner('REVIVED!', color: Palette.cyan);
    audio.play(Sfx.shield);
    hud.sync(sim);
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final sim = _sim;
    if (sim == null) return;
    final frame = math.min(dt, Physics.maxFrameDelta);
    _time += frame;

    sim.update(frame);
    _drainEvents(sim);
    effects.update(frame);

    // Cosmetic cannon motion: recoil, wheel spin and lean.
    _recoil = math.max(0, _recoil - frame * 40);
    _muzzle = math.max(0, _muzzle - frame * 12);
    final dx = sim.cannonX - _lastCannonX;
    _lastCannonX = sim.cannonX;
    _wheel += dx / (13 * CannonSpec.artScale);
    final vx = dx / math.max(frame, 1e-3);
    final targetTilt = (vx / 1400).clamp(-0.12, 0.12);
    _tilt += (targetTilt - _tilt) * math.min(1, frame * 12);

    if (sim.isFinished && !_endReported) {
      if (_endDelay < 0) _endDelay = sim.isStageCleared ? 1.4 : 1.0;
      _endDelay -= frame;
      if (_endDelay <= 0) {
        _endReported = true;
        onRunEnded(sim);
      }
    }
    hud.sync(sim);
  }

  void _drainEvents(GameSimulation sim) {
    if (sim.events.isEmpty) return;
    for (final event in sim.drainEvents()) {
      switch (event) {
        case ShotFired():
          _recoil = 3;
          _muzzle = 1;
          audio.play(Sfx.shoot);
        case BallHit(:final x, :final y, :final armored):
          effects.burst(
            x,
            y,
            armored ? const Color(0xFFD9C7B5) : Palette.yellow,
            count: 2,
            speed: 140,
            size: 2.2,
          );
          audio.play(armored ? Sfx.armor : Sfx.hit, volume: armored ? 0.35 : 1);
        case BallDestroyed(:final x, :final y, :final tier, :final kind):
          final color = switch (kind) {
            EnemyKind.skyray => const Color(0xFFE05CFF),
            EnemyKind.treasure => const Color(0xFFFFC83A),
            _ => BallArt.colorForTier(tier),
          };
          final r = switch (kind) {
            EnemyKind.skyray => EnemySpec.skyrayRadius,
            EnemyKind.treasure => EnemySpec.treasureRadius,
            _ => BallSpec.radius[tier],
          };
          if (kind == EnemyKind.treasure) {
            effects
              ..burst(x, y, Palette.gold, count: 14, speed: 220, size: 3)
              ..floatText(x, y - 30, 'TREASURE!', Palette.gold, size: 18);
            audio.play(Sfx.coin);
          }
          effects
            ..shatter(x, y, color, r)
            ..ring(x, y, r * 2.2, color, life: 0.35, width: 4);
          if (tier >= 3) effects.addShake(3);
          audio.play(Sfx.pop, volume: 0.7 + tier * 0.08);
          haptics.trigger(Haptic.light);
        case ArmorBroken(:final x, :final y, :final radius):
          effects
            ..rocks(x, y, radius)
            ..floatText(x, y - radius - 8, 'CRACKED!', const Color(0xFFE9E2DA));
          effects.addShake(2);
          audio.play(Sfx.armor);
          haptics.trigger(Haptic.medium);
        case BallBounced(:final x, :final tier):
          if (tier >= 2) {
            effects.smoke(
              x,
              sim.floorY,
              10,
              count: 2,
              color: const Color(0xFFE8F5D8),
            );
          }
          if (tier >= 4 && sim.boss != null) {
            effects.addShake(6);
            audio.play(Sfx.explode, volume: 0.6);
          }
        case SplashHit(:final x, :final y, :final radius):
          effects
            ..ring(x, y, radius, Palette.orange, life: 0.2, width: 3)
            ..burst(
              x,
              y,
              const Color(0xFFFFB13D),
              count: 3,
              speed: 110,
              size: 2.5,
            );
        case ArcZap(:final points):
          effects.lightning([for (final p in points) Offset(p.x, p.y)]);
          audio.play(Sfx.zap);
        case EnemyFrozen(:final x, :final y):
          effects.burst(
            x,
            y,
            const Color(0xFFBDF3FF),
            count: 6,
            speed: 120,
            size: 2.5,
          );
          audio.play(Sfx.freeze, volume: 0.5);
        case HazardHit(:final x, :final y, :final kind):
          effects.burst(x, y, hazardColor(kind), count: 2, speed: 100, size: 2);
        case HazardDetonated(:final kind, :final x, :final y, :final radius):
          switch (kind) {
            case HazardKind.blaze:
              effects.explosion(x, y, radius);
              effects.addShake(7);
              audio.play(Sfx.explode);
            case HazardKind.frost:
              effects.frostNova(x, y, radius);
              effects.addShake(3);
              audio.play(Sfx.freeze);
            case HazardKind.storm:
              effects
                ..ring(
                  x,
                  y,
                  radius * 0.5,
                  hazardColor(kind),
                  life: 0.4,
                  width: 6,
                )
                ..burst(x, y, const Color(0xFFFFF27A), count: 14, speed: 260);
              effects.addShake(4);
              audio.play(Sfx.zap);
          }
          effects.shatter(x, y, hazardColor(kind), HazardSpec.radius);
          haptics.trigger(Haptic.heavy);
        case ChainProgress(:final count):
          effects.showChain(count);
          audio.play(Sfx.chain, volume: math.min(1, 0.5 + count * 0.05));
        case ChainEnded(:final count, :final bonusCoins):
          if (bonusCoins > 0) {
            effects.floatText(
              sim.cannonX,
              sim.floorY - 90,
              'CHAIN x$count  +$bonusCoins',
              Palette.gold,
              size: 17,
            );
            audio.play(Sfx.coin);
          }
        case ShotDropped(:final x, :final y):
          effects.burst(
            x,
            y,
            const Color(0xFFFF73E8),
            count: 4,
            speed: 90,
            size: 2,
          );
        case CoinCollected(:final x, :final y, :final value):
          if (value > 0) {
            effects
              ..burst(x, y, Palette.gold, count: 4, speed: 90, size: 2.4)
              ..floatText(
                sim.cannonX,
                sim.floorY - 70,
                '+$value',
                Palette.gold,
              );
            audio.play(Sfx.coin);
          }
        case PowerUpCollected(:final type):
          effects.floatText(
            sim.cannonX,
            sim.floorY - 80,
            '+1 ${IconArt.labelFor(type)}',
            IconArt.colorFor(type),
          );
          audio.play(Sfx.powerup);
          haptics.trigger(Haptic.medium);
        case PowerUpActivated(:final type, :final x, :final y):
          _onPowerUp(type, x, y);
        case ShieldBroken(:final x, :final y):
          effects
            ..burst(x, y, Palette.cyan, count: 18, speed: 260)
            ..ring(x, y, 70, Palette.cyan, life: 0.5);
          effects.addShake(4);
          audio.play(Sfx.shield);
          haptics.trigger(Haptic.heavy);
        case PlayerHurt(:final x, :final y, :final hullLeft):
          effects
            ..burst(x, y, Palette.coral, count: 16, speed: 240)
            ..floatText(
              x,
              y - 40,
              hullLeft == 1 ? 'LAST HULL!' : 'HIT!',
              Palette.coral,
              size: 18,
            );
          effects.addShake(7);
          audio.play(Sfx.hurt);
          haptics.trigger(Haptic.heavy);
        case PlayerDestroyed(:final x, :final y):
          effects
            ..explosion(x, y, 90)
            ..rocks(x, y, 30);
          effects.addShake(10);
          audio.play(Sfx.gameover);
          haptics.trigger(Haptic.heavy);
        case WaveStarted(:final wave):
          final total = sim.plan.waveCount;
          final b = sim.boss;
          final isBoss = b != null && !b.dead && wave == total;
          if (isBoss) {
            effects.showBanner('BOSS!', sub: b.def.name, color: Palette.coral);
            audio.play(Sfx.roar);
            effects.addShake(8);
          } else if (total == null || wave > 1) {
            // Stage starts use the Flutter title card instead.
            effects.showBanner(
              total == null ? 'WAVE $wave' : 'WAVE $wave/$total',
            );
            if (wave > 1) audio.play(Sfx.wave);
          }
        case WaveCleared():
          if (!sim.isStageCleared) haptics.trigger(Haptic.medium);
        case BossHit(:final x, :final y, :final plate):
          effects.burst(
            x,
            y,
            plate ? const Color(0xFFD9C7B5) : const Color(0xFFFFB0F0),
            count: 2,
            speed: 140,
            size: 2.4,
          );
          audio.play(plate ? Sfx.armor : Sfx.hit, volume: 0.5);
        case BossPlateBroken(:final x, :final y):
          effects
            ..rocks(x, y, 30)
            ..explosion(
              x,
              y,
              50,
              core: const Color(0xFFFFF0C0),
              outer: const Color(0xFFB98A5A),
            )
            ..floatText(x, y - 40, 'ARMOR BROKEN!', Palette.yellow, size: 18);
          effects.addShake(6);
          audio.play(Sfx.armor);
          haptics.trigger(Haptic.heavy);
        case BossPhaseChanged(:final phase):
          final b = sim.boss;
          final last = b != null && phase == b.phaseCount;
          effects.showBanner(
            'PHASE $phase',
            sub: last ? 'Final phase!' : _phaseHint(b),
            color: Palette.coral,
          );
          if (b != null) {
            effects.ring(
              b.x,
              b.y,
              b.coreRadius * 2.4,
              b.def.colorFor(phase),
              life: 0.6,
              width: 6,
            );
          }
          effects.addShake(8);
          audio.play(Sfx.roar);
          haptics.trigger(Haptic.heavy);
        case BossDefeated(:final x, :final y):
          final color =
              sim.boss?.def.colorFor(sim.boss!.phase) ??
              const Color(0xFFFF4B5C);
          for (var i = 0; i < 4; i++) {
            effects.explosion(
              x + (i - 1.5) * 30,
              y + (i.isEven ? -20 : 20),
              90,
            );
          }
          effects
            ..shatter(x, y, color, 70)
            ..shatter(x, y, Palette.gold, 40)
            ..ring(x, y, 220, color, life: 0.8, width: 8)
            ..flash = 1;
          effects.addShake(12);
          audio.play(Sfx.explode);
          audio.play(Sfx.roar, volume: 0.6);
          haptics.trigger(Haptic.heavy);
        case BossShielded(:final x, :final y):
          effects
            ..ring(x, y, 26, Palette.cyan, life: 0.25, width: 3)
            ..burst(x, y, const Color(0xFFBDF3FF), count: 3, speed: 120);
          audio.play(Sfx.armor, volume: 0.25);
        case ZapStrike(:final x, :final halfWidth, :final hit):
          effects
            ..lightning([
              Offset(x, 0),
              Offset(x - halfWidth * 0.4, sim.floorY * 0.35),
              Offset(x + halfWidth * 0.4, sim.floorY * 0.7),
              Offset(x, sim.floorY),
            ])
            ..burst(
              x,
              sim.floorY - 4,
              const Color(0xFFFFF27A),
              count: 10,
              speed: 200,
            );
          effects.addShake(hit ? 6 : 3);
          audio.play(Sfx.zap);
        case ZoneArmed(:final kind, :final x, :final halfWidth):
          if (kind == ZoneKind.lava) {
            effects.burst(
              x,
              sim.floorY - 8,
              const Color(0xFFFF7A2B),
              count: 12,
              speed: 180,
            );
            audio.play(Sfx.explode, volume: 0.4);
          } else {
            effects.frostNova(x, sim.floorY - 10, halfWidth);
            audio.play(Sfx.freeze, volume: 0.6);
          }
        case CannonChilled(:final x, :final y):
          effects
            ..ring(x, y, 60, const Color(0xFFBDF3FF), life: 0.5)
            ..floatText(
              x,
              y - 50,
              'FROZEN!',
              const Color(0xFFBDF3FF),
              size: 18,
            );
          haptics.trigger(Haptic.medium);
        case WeakPointChanged(:final x, :final y, :final open):
          if (open) {
            effects
              ..ring(x, y, 120, const Color(0xFFFFF27A), life: 0.5, width: 5)
              ..floatText(x, y + 60, 'WEAK POINT!', Palette.yellow, size: 18);
            audio.play(Sfx.powerup, volume: 0.6);
          }
        case BossPulled(:final x, :final y):
          effects.ring(x, y, 200, const Color(0xFF8A9BFF), life: 0.7, width: 5);
          audio.play(Sfx.wave, volume: 0.6);
        case BossHeadRegrown(:final x, :final y):
          effects
            ..ring(x, y, 50, Palette.green, life: 0.5)
            ..floatText(x, y - 40, 'REGROWN!', Palette.green);
        case TreasureEscaped(:final x, :final y):
          effects.floatText(
            x.clamp(40, sim.width - 40),
            y,
            'ESCAPED',
            const Color(0xFFFFE6A0),
          );
        case StageCleared():
          effects.showBanner('LEVEL CLEAR!', color: Palette.green);
          audio.play(Sfx.stageclear);
          haptics.trigger(Haptic.medium);
      }
    }
  }

  static String _phaseHint(Boss? b) {
    if (b == null) return '';
    final attacks = b.phaseDef.attacks;
    if (b.hasWeakWindows) return 'Strike when the rift opens!';
    if (attacks.contains(BossAttack.freeze)) return 'Mind the frozen ground!';
    if (attacks.contains(BossAttack.lava)) return 'The floor is lava!';
    if (attacks.contains(BossAttack.zap)) return 'Lightning incoming!';
    if (attacks.contains(BossAttack.slam)) return 'Watch for the slam!';
    return 'It is getting angry!';
  }

  void _onPowerUp(PowerUpType type, double x, double y) {
    final color = IconArt.colorFor(type);
    switch (type) {
      case PowerUpType.bomb:
        effects.explosion(x, y, PowerUpSpec.bombRadius);
        effects.addShake(8);
        audio.play(Sfx.bomb);
        haptics.trigger(Haptic.heavy);
      case PowerUpType.shield:
        effects.ring(x, y, 60, color, life: 0.5);
        audio.play(Sfx.shield);
        haptics.trigger(Haptic.medium);
      case PowerUpType.slowMotion:
      case PowerUpType.powerShot:
        effects.ring(x, y, 90, color, life: 0.5);
        audio.play(Sfx.powerup);
        haptics.trigger(Haptic.medium);
    }
  }

  // ---------------------------------------------------------------- render

  @override
  void render(Canvas canvas) {
    final sim = _sim;
    _renderWorld(canvas, sim);
    if (sim == null) return;

    canvas.save();
    final shake = effects.shakeOffset();
    canvas.translate(
      _origin.dx + shake.dx * _scale,
      _origin.dy + shake.dy * _scale,
    );
    canvas.scale(_scale);

    for (final t in sim.telegraphs) {
      _art.telegraph(canvas, t, sim.floorY, _time);
    }
    for (final z in sim.zones) {
      _art.floorZone(canvas, z, sim.floorY, _time);
    }
    if (!effects.reducedMotion) _renderMotes(canvas, sim);
    _renderShadows(canvas, sim);
    _renderSpawnMarkers(canvas, sim);
    effects.renderBack(canvas);
    for (final hz in sim.hazards) {
      _art.hazard(canvas, hz, _time);
    }
    _renderPickups(canvas, sim);
    _renderBullets(canvas, sim);
    for (final s in sim.shots) {
      _art.enemyShot(canvas, s);
    }
    _renderBoss(canvas, sim);
    _renderCreatures(canvas, sim);
    _renderCannon(canvas, sim);
    effects.render(canvas);
    canvas.restore();

    if (sim.slowActive) {
      _paint.color = Palette.purple.withValues(alpha: 0.1);
      canvas.drawRect(Offset.zero & Size(size.x, size.y), _paint);
    }
    effects.renderOverlay(
      canvas,
      Size(size.x, size.y),
      Offset(size.x / 2, _origin.dy + sim.arenaHeight * _scale * 0.4),
      (_scale / 2.4).clamp(0.6, 1.6),
    );
    super.render(canvas);
  }

  void _renderWorld(Canvas canvas, GameSimulation? sim) {
    // Parallax: layers shift opposite to the cannon, more for nearer ones.
    final offset = sim == null ? 0.0 : (sim.cannonX / sim.width - 0.5);
    for (final layer in WorldLayer.values) {
      final pic = _layers[layer];
      if (pic == null) continue;
      var dx = -offset * WorldArt.parallax[layer]! * size.x;
      if (layer == WorldLayer.clouds) {
        // Clouds drift slowly and wrap around.
        final span = size.x * (1 + WorldArt.overscan);
        dx += (_time * 6) % span;
        pic.draw(canvas, dx - span);
      }
      pic.draw(canvas, dx);
    }
    _ground?.draw(canvas, 0);
  }

  void _renderSpawnMarkers(Canvas canvas, GameSimulation sim) {
    for (final pending in sim.pendingSpawns) {
      final blink = (math.sin(_time * 18) + 1) / 2;
      final flyer =
          pending.kind == EnemyKind.skyray ||
          pending.kind == EnemyKind.treasure;
      final color = switch (pending.kind) {
        EnemyKind.skyray => const Color(0xFFE05CFF),
        EnemyKind.treasure => const Color(0xFFFFC83A),
        _ => BallArt.colorForTier(pending.tier),
      };
      _paint.color = color.withValues(alpha: 0.45 + 0.5 * blink);
      if (flyer) {
        // Side arrow at flight height.
        final y = sim.floorY * 0.23;
        final x = pending.direction > 0 ? 8.0 : sim.width - 8;
        final d = pending.direction.toDouble();
        canvas.drawPath(
          Path()..addPolygon([
            Offset(x + d * 18, y),
            Offset(x, y - 12),
            Offset(x, y + 12),
          ], true),
          _paint,
        );
        continue;
      }
      const top = 92.0;
      final x = pending.x;
      canvas.drawPath(
        Path()..addPolygon([
          Offset(x, top + 20),
          Offset(x - 13, top),
          Offset(x + 13, top),
        ], true),
        _paint,
      );
      _paint.color = color.withValues(alpha: 0.12 + 0.12 * blink);
      canvas.drawRect(Rect.fromLTWH(x - 2, top + 20, 4, 70), _paint);
    }
  }

  void _renderPickups(Canvas canvas, GameSimulation sim) {
    for (final p in sim.pickups) {
      // Blink during the last two seconds of a pickup's life.
      if (p.life < 2 && (p.life * 8).floor().isEven) continue;
      final bob = p.grounded ? math.sin(_time * 6 + p.x) * 1.5 : 0.0;
      final c = Offset(p.x, p.y + bob);
      switch (p.kind) {
        case PickupKind.coin:
          IconArt.coin(canvas, c, 15);
        case PickupKind.powerUp:
          _paint.color = IconArt.colorFor(p.powerUp!).withValues(alpha: 0.35);
          canvas.drawCircle(c, 16, _paint);
          IconArt.powerUp(canvas, p.powerUp!, c, 26);
      }
    }
  }

  void _renderBullets(Canvas canvas, GameSimulation sim) {
    final r = BulletSpec.radius * (sim.powerShotActive ? 1.35 : 1);
    for (final b in sim.bullets) {
      final color = b.powered ? Palette.purple : elementColor(b.element);
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.scale(r);
      // Tail, with one cached unit-space gradient per colour.
      _paint.shader = _tailShaders.putIfAbsent(
        color.toARGB32(),
        () => Gradient.linear(Offset.zero, const Offset(0, 9), [
          color.withValues(alpha: 0.75),
          color.withValues(alpha: 0),
        ]),
      );
      canvas.drawRRect(_tail, _paint);
      _paint.shader = null;
      // A pointed bolt (round heads side by side read as "eyes").
      _paint.color = const Color(0xFF1C1830);
      canvas.drawPath(_boltOutline, _paint);
      _paint.color = color;
      canvas.drawPath(_bolt, _paint);
      _paint.color = const Color(0xE6FFFFFF);
      canvas.drawPath(_boltCore, _paint);
      canvas.restore();
    }
  }

  final Map<int, Shader> _tailShaders = {};
  static final RRect _tail = RRect.fromLTRBR(
    -0.9,
    0,
    0.9,
    9,
    const Radius.circular(1),
  );

  // Bolt shapes in bullet-radius units, tip at the collision point.
  static final Path _bolt = Path()
    ..moveTo(0, -1.9)
    ..quadraticBezierTo(0.95, -0.4, 0.75, 1.6)
    ..lineTo(-0.75, 1.6)
    ..quadraticBezierTo(-0.95, -0.4, 0, -1.9)
    ..close();
  static final Path _boltOutline = Path()
    ..moveTo(0, -2.5)
    ..quadraticBezierTo(1.35, -0.4, 1.1, 1.95)
    ..lineTo(-1.1, 1.95)
    ..quadraticBezierTo(-1.35, -0.4, 0, -2.5)
    ..close();
  static final Path _boltCore = Path()
    ..moveTo(0, -1.2)
    ..quadraticBezierTo(0.35, -0.2, 0.25, 0.9)
    ..lineTo(-0.25, 0.9)
    ..quadraticBezierTo(-0.35, -0.2, 0, -1.2)
    ..close();

  void _renderCreatures(Canvas canvas, GameSimulation sim) {
    for (final b in sim.balls) {
      final flash = b.hitFlash / BallSpec.hitFlashTime;
      switch (b.kind) {
        case EnemyKind.skyray:
          _art.skyray(
            canvas,
            x: b.x,
            y: b.y,
            r: b.radius,
            text: formatCompact(b.displayHp),
            phase: b.flyPhase,
            dropWarning: b.dropTimer < EnemySpec.skyrayDropTelegraph
                ? 1 - b.dropTimer / EnemySpec.skyrayDropTelegraph
                : 0,
            flash: flash,
            frozen: b.isFrozen,
            dir: b.vx.sign,
          );
        case EnemyKind.treasure:
          _art.treasure(
            canvas,
            x: b.x,
            y: b.y,
            r: b.radius,
            text: formatCompact(b.displayHp),
            time: _time + b.id,
            flash: flash,
          );
        case EnemyKind.geode when b.armored:
          _art.geode(
            canvas,
            x: b.x,
            y: b.y,
            r: b.radius,
            coreColor: BallArt.colorForTier(b.tier),
            text: formatCompact(b.displayHp),
            armorFraction: b.maxArmor > 0 ? b.armor / b.maxArmor : 0,
            variant: b.id,
            flash: flash,
            squash: b.squash / BallSpec.squashTime,
            frozen: b.isFrozen,
            spin: _roll(b),
          );
        case EnemyKind.geode:
        case EnemyKind.shard:
          _art.shard(
            canvas,
            x: b.x,
            y: b.y,
            r: b.radius,
            color: BallArt.colorForTier(b.tier),
            text: formatCompact(b.displayHp),
            variant: b.id,
            flash: flash,
            squash: b.squash / BallSpec.squashTime,
            frozen: b.isFrozen,
            chilled: b.chill > 0,
            spin: _roll(b),
          );
      }
      final affinity = b.affinity;
      if (affinity != null) {
        _art.affinityRing(canvas, b.x, b.y, b.radius, affinity);
      }
    }
  }

  /// Rolling angle derived from position, so crystals tumble as they
  /// travel without any extra simulation state.
  static double _roll(Ball b) => b.x / b.radius * 0.6 + b.id * 0.7;

  /// Soft ground shadows that shrink as creatures rise, for a sense of
  /// depth and to make landing spots readable.
  void _renderShadows(Canvas canvas, GameSimulation sim) {
    final floor = sim.floorY;
    for (final b in sim.balls) {
      final r = b.radius;
      final height = (floor - b.y - r).clamp(0.0, floor);
      final k = 1 - (height / floor).clamp(0.0, 1.0) * 0.6;
      _paint.color = Color.fromRGBO(20, 30, 20, 0.26 * k * k);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(b.x, floor + 3),
          width: r * 1.9 * k,
          height: r * 0.42 * k,
        ),
        _paint,
      );
    }
  }

  /// Drifting light motes in the sky, purely decorative.
  void _renderMotes(Canvas canvas, GameSimulation sim) {
    for (var i = 0; i < 14; i++) {
      final speed = 6 + (i * 7) % 11;
      final x = (i * 53.0 + _time * speed) % (sim.width + 40) - 20;
      final y =
          sim.floorY * (0.12 + ((i * 37) % 70) / 100) +
          math.sin(_time * 0.9 + i) * 10;
      final twinkle = 0.5 + 0.5 * math.sin(_time * 2.2 + i * 1.7);
      _paint.color = Color.fromRGBO(255, 248, 210, 0.18 + 0.32 * twinkle);
      canvas.drawCircle(Offset(x, y), 1.4 + (i % 3) * 0.7, _paint);
    }
  }

  void _renderBoss(Canvas canvas, GameSimulation sim) {
    final b = sim.boss;
    if (b == null || b.dead) return;
    _art.boss(canvas, b, _time);
  }

  void _renderCannon(Canvas canvas, GameSimulation sim) {
    if (sim.isOver) return;
    final invulnerable = sim.invulnerableTimer > 0;
    if (invulnerable && (_time * 14).floor().isEven) return;
    CannonArt.draw(
      canvas,
      x: sim.cannonX,
      baseY: sim.floorY,
      skin: skin,
      level: setup.loadout.cannonLevel,
      recoil: _recoil,
      tilt: _tilt,
      wheelAngle: _wheel,
      glowPulse: (math.sin(_time * 5) + 1) / 2,
      core: elementColor(sim.element),
      muzzleFlash: _muzzle,
      scale: CannonSpec.artScale,
    );
    if (sim.cannonSlowed) {
      // Frosted cannon: icy coat while steering is slowed.
      final c = Offset(sim.cannonX, sim.floorY - 30);
      _paint.color = const Color(0x667FE6FF);
      canvas.drawCircle(c, 44, _paint);
      _shieldPaint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xCCE8FBFF);
      canvas.drawCircle(c, 44, _shieldPaint);
    }
    if (sim.shieldActive) {
      final c = Offset(sim.cannonX, sim.floorY - 34);
      final pulse = 1 + math.sin(_time * 6) * 0.03;
      _shieldPaint
        ..style = PaintingStyle.fill
        ..shader = Gradient.radial(
          c,
          46 * pulse,
          [
            Palette.cyan.withValues(alpha: 0),
            Palette.cyan.withValues(alpha: 0.12),
            Palette.cyan.withValues(alpha: 0.45),
          ],
          const [0, 0.75, 1],
        );
      canvas.drawCircle(c, 56 * pulse, _shieldPaint);
      _shieldPaint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Palette.cyan.withValues(alpha: 0.9);
      canvas.drawCircle(c, 56 * pulse, _shieldPaint);
    }
  }

  @override
  void onRemove() {
    for (final p in _layers.values) {
      p.dispose();
    }
    _layers.clear();
    _ground?.dispose();
    _ground = null;
    _art.dispose();
    super.onRemove();
  }
}

/// A backdrop layer rasterised once and drawn as a single image.
class _Baked {
  _Baked(this.image, this.dst);

  factory _Baked.paint(Rect dst, double ratio, void Function(Canvas) paint) {
    final rec = PictureRecorder();
    final c = Canvas(rec)
      ..scale(ratio)
      ..translate(-dst.left, -dst.top);
    paint(c);
    final picture = rec.endRecording();
    final image = picture.toImageSync(
      math.max(1, (dst.width * ratio).ceil()),
      math.max(1, (dst.height * ratio).ceil()),
    );
    picture.dispose();
    return _Baked(image, dst);
  }

  final Image image;
  final Rect dst;
  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  void draw(Canvas canvas, double dx) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst.shift(Offset(dx, 0)),
      _paint,
    );
  }

  void dispose() => image.dispose();
}

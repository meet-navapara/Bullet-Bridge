import 'dart:math' as math;

import '../../config/balance.dart';
import '../../config/bosses.dart';
import '../../config/campaign.dart';
import 'boss.dart';
import 'entities.dart';
import 'seeded_random.dart';
import 'wave_director.dart';

/// The complete, deterministic rules of a single run.
///
/// No Flutter or Flame imports: the renderer reads the public state and
/// drains [events]; tests drive [step] directly.
class GameSimulation {
  GameSimulation({
    required this.loadout,
    required int seed,
    required double arenaHeight,
    Map<PowerUpType, int>? startingPowerUps,
    this.plan = const EndlessPlan(),
  }) : _rng = SeededRandom(seed),
       arenaHeight = arenaHeight.clamp(
         Physics.minArenaHeight,
         Physics.maxArenaHeight,
       ) {
    cannonX = width / 2;
    hull = loadout.hull;
    inventory = {
      PowerUpType.bomb: PowerUpSpec.startBombs,
      PowerUpType.slowMotion: PowerUpSpec.startSlow,
      PowerUpType.shield: math.max(0, loadout.startingShieldLevel - 1),
      PowerUpType.powerShot: PowerUpSpec.startPowerShot,
    };
    startingPowerUps?.forEach((type, extra) {
      inventory[type] = math.min(
        PowerUpSpec.maxInventory,
        inventory[type]! + extra,
      );
    });
    if (loadout.startingShieldLevel > 0) {
      // The starting shield lasts until it absorbs a hit.
      shieldTimer = double.infinity;
    }
    _fireTimer = 0.25;
    _startWave(1);
  }

  final Loadout loadout;
  final RunPlan plan;
  final SeededRandom _rng;
  final double width = Physics.worldWidth;
  final double arenaHeight;
  double get floorY => arenaHeight - Physics.floorHeight;

  final List<Ball> balls = [];
  final List<Bullet> bullets = [];
  final List<Pickup> pickups = [];
  final List<PendingSpawn> pendingSpawns = [];
  final List<Hazard> hazards = [];
  final List<EnemyShot> shots = [];
  final List<Blast> blasts = [];
  final List<Telegraph> telegraphs = [];
  final List<FloorZone> zones = [];
  final List<GameEvent> events = [];
  Boss? boss;

  late double cannonX;
  late final Map<PowerUpType, int> inventory;
  RunPhase phase = RunPhase.playing;
  Element element = Element.kinetic;

  late int hull;
  int hullLost = 0;
  int wave = 0;
  int score = 0;
  int coins = 0;
  int ballsDestroyed = 0;
  int powerUpsUsed = 0;
  int wavesCleared = 0;
  int chainCount = 0;
  int bestChain = 0;
  bool bossDefeated = false;
  double elapsed = 0;
  bool revived = false;

  double slowTimer = 0;
  double powerShotTimer = 0;
  double shieldTimer = 0;
  double invulnerableTimer = 0;
  double cooldownTimer = 0;
  double intermissionTimer = 0;
  double chainTimer = 0;

  /// While > 0 the cannon is frosted and steers slowly.
  double cannonSlowTimer = 0;

  /// Difficulty of the current wave; hazards and blasts scale with it.
  double difficulty = 1;

  // Speed and durability of the current wave (see [SpeedSpec]).
  double _pace = SpeedSpec.startPace;
  double _drift = 1;
  BounceProfile _bounce = BounceProfile.normal;
  double? _spawnGapOverride;
  double? _scaleOverride;

  /// Pace of the current wave, before slow motion.
  double get pace => _pace;

  /// Horizontal drift multiplier of the current wave.
  double get drift => _drift;
  BounceProfile get bounce => _bounce;

  /// Coin multiplier of the campaign level (1 outside the campaign).
  double get coinScale => switch (plan) {
    final StagePlan p => p.level.coinScale,
    _ => 1,
  };

  final List<WaveSpawn> _spawnQueue = [];
  double _spawnTimer = 0;
  double _fireTimer = 0;
  double _accumulator = 0;
  double _coinRemainder = 0;
  double _scoreRemainder = 0;
  int _nextId = 0;
  final List<Ball> _newBalls = [];

  bool get isOver => phase == RunPhase.gameOver;
  bool get isStageCleared => phase == RunPhase.stageCleared;

  /// True once the run has ended either way; nothing updates afterwards.
  bool get isFinished => isOver || isStageCleared;
  bool get shieldActive => shieldTimer > 0;
  bool get slowActive => slowTimer > 0;
  bool get powerShotActive => powerShotTimer > 0;
  bool get cannonSlowed => cannonSlowTimer > 0;

  /// Creature time scale: the wave pace times any slow motion. This is the
  /// only time scale creatures, shots and bosses move with.
  double get ballTimeScale =>
      _pace * (slowActive ? PowerUpSpec.slowMotionScale : 1.0);

  /// Durability scale of the current wave.
  double get scale => _scaleOverride ?? WaveDirector.scaleAt(difficulty);

  /// 3 stars for a flawless run, 2 for one hit taken, otherwise 1.
  int get stars => hullLost == 0 ? 3 : (hullLost == 1 ? 2 : 1);

  /// Remaining enemies in this wave including unspawned ones, for the HUD.
  int get remainingInWave =>
      balls.length +
      pendingSpawns.length +
      _spawnQueue.length +
      (boss != null && !boss!.dead ? 1 : 0);

  /// Advances the simulation by a real frame delta using fixed sub-steps.
  void update(double dt) {
    if (isFinished || !dt.isFinite || dt <= 0) return;
    _accumulator += math.min(dt, Physics.maxFrameDelta);
    while (_accumulator >= Physics.fixedStep && !isFinished) {
      step(Physics.fixedStep);
      _accumulator -= Physics.fixedStep;
    }
  }

  /// Moves the cannon by a horizontal world-space delta, clamped to walls.
  void moveCannonBy(double dx) {
    if (isFinished || !dx.isFinite) return;
    setCannonX(cannonX + (cannonSlowed ? dx * BossSpec.freezeMoveScale : dx));
  }

  void setCannonX(double x) {
    cannonX = x.clamp(
      CannonSpec.visualHalfWidth,
      width - CannonSpec.visualHalfWidth,
    );
  }

  /// Switches the projectile element if it is unlocked.
  bool setElement(Element e) {
    if (!loadout.elements.contains(e) || isFinished) return false;
    element = e;
    return true;
  }

  /// Test/debug hook: removes enemies and hazards that have not spawned yet
  /// so a test can set up an exact scenario.
  void debugClearSpawnQueue() {
    _spawnQueue.clear();
    pendingSpawns.clear();
    hazards.clear();
  }

  List<GameEvent> drainEvents() {
    final drained = List<GameEvent>.of(events);
    events.clear();
    return drained;
  }

  // ---------------------------------------------------------------------
  // Fixed step
  // ---------------------------------------------------------------------

  void step(double h) {
    if (isFinished) return;
    elapsed += h;
    _tickTimers(h);
    _updateWave(h);
    if (isFinished) return;
    _fire(h);
    _updateBullets(h);
    _updateBalls(h);
    _updateBoss(h);
    _updateShots(h);
    _updateTelegraphs(h);
    _updateZones(h);
    _processBlasts(h);
    _updatePickups(h);
    _checkCannonCollision();
    _cleanup();
  }

  void _tickTimers(double h) {
    if (slowTimer > 0) slowTimer = math.max(0, slowTimer - h);
    if (powerShotTimer > 0) powerShotTimer = math.max(0, powerShotTimer - h);
    if (shieldTimer > 0 && shieldTimer.isFinite) {
      shieldTimer = math.max(0, shieldTimer - h);
    }
    if (invulnerableTimer > 0) {
      invulnerableTimer = math.max(0, invulnerableTimer - h);
    }
    if (cooldownTimer > 0) cooldownTimer = math.max(0, cooldownTimer - h);
    if (cannonSlowTimer > 0) {
      cannonSlowTimer = math.max(0, cannonSlowTimer - h);
    }
    for (final hz in hazards) {
      if (hz.hitFlash > 0) hz.hitFlash = math.max(0, hz.hitFlash - h);
    }
    if (chainTimer > 0) {
      chainTimer -= h;
      if (chainTimer <= 0) _endChain();
    }
  }

  // ---------------------------------------------------------------------
  // Waves
  // ---------------------------------------------------------------------

  void _startWave(int number) {
    wave = number;
    phase = RunPhase.playing;
    final wavePlan = plan.wave(number, _rng);
    difficulty = wavePlan.difficulty;
    _scaleOverride = wavePlan.scale;
    _pace = (wavePlan.pace ?? WaveSpec.paceAt(difficulty)).clamp(
      SpeedSpec.minPace,
      SpeedSpec.maxPace,
    );
    _drift = (wavePlan.drift ?? WaveSpec.speedMultiplier(number)).clamp(
      1.0,
      SpeedSpec.maxDrift,
    );
    _bounce = wavePlan.bounce;
    _spawnGapOverride = wavePlan.spawnGap;
    _spawnQueue
      ..clear()
      ..addAll(wavePlan.spawns);
    _spawnTimer = WaveSpec.firstSpawnDelay;
    final hp = _hazardHp;
    for (final p in wavePlan.hazards) {
      hazards.add(
        Hazard(
          id: _nextId++,
          kind: p.kind,
          x: p.xFrac * width,
          y: p.yFrac * floorY,
          maxHp: hp,
        ),
      );
    }
    final def = wavePlan.boss;
    if (def != null) {
      final chapter = math.max(1, Bosses.campaign.indexOf(def) + 1);
      boss =
          Boss(
              def: def,
              balls: BossSpec.ballPlan(
                chapter,
                _rng.nextDouble,
                supplyScale: def.ballSupplyScale,
              ),
              throwInterval: BossSpec.throwIntervalFor(chapter),
              homeY: arenaHeight * BossSpec.hoverFraction,
              x: width / 2,
            )
            ..transition = BossSpec.entranceTime
            ..armPhase();
    }
    events.add(WaveStarted(number));
  }

  double get _hazardHp =>
      math.max(2.0, (scale * HazardSpec.hpFactor).roundToDouble());

  void _updateWave(double h) {
    if (phase == RunPhase.intermission) {
      intermissionTimer -= h;
      if (intermissionTimer <= 0) _startWave(wave + 1);
      return;
    }

    // Telegraphed spawns drop in once their warning expires.
    for (final pending in pendingSpawns) {
      pending.timer -= h;
      if (pending.timer <= 0) _dropIn(pending);
    }
    pendingSpawns.removeWhere((p) => p.timer <= 0);

    final bossAlive = boss != null && !boss!.dead;
    if (_spawnQueue.isNotEmpty) {
      _spawnTimer -= h;
      if (_spawnTimer <= 0 && balls.length < WaveSpec.maxAliveBalls) {
        _telegraph(_spawnQueue.removeAt(0));
        _spawnTimer = _spawnGapOverride ?? WaveSpec.spawnGap(wave);
      }
    } else if (pendingSpawns.isEmpty && balls.isEmpty && !bossAlive) {
      _clearWave();
    }
  }

  void _telegraph(WaveSpawn spawn) {
    final r = switch (spawn.kind) {
      EnemyKind.skyray => EnemySpec.skyrayRadius,
      EnemyKind.treasure => EnemySpec.treasureRadius,
      _ => BallSpec.radius[spawn.tier],
    };
    final leftX = r + 8;
    final rightX = width - r - 8;
    // Fairness: never drop a ball onto the side the cannon is hugging.
    final bool fromLeft;
    if (cannonX < width * 0.3) {
      fromLeft = false;
    } else if (cannonX > width * 0.7) {
      fromLeft = true;
    } else {
      fromLeft = _rng.nextBool();
    }
    pendingSpawns.add(
      PendingSpawn(
        x: fromLeft ? leftX : rightX,
        tier: spawn.tier,
        hp: spawn.hp,
        direction: fromLeft ? 1 : -1,
        timer: WaveSpec.spawnTelegraph,
        kind: spawn.kind,
        armor: spawn.armor,
        affinity: spawn.affinity,
        speedFactor: spawn.speedFactor,
      ),
    );
  }

  void _dropIn(PendingSpawn pending) {
    if (pending.kind == EnemyKind.treasure) {
      const r = EnemySpec.treasureRadius;
      final flyY = floorY * _rng.range(0.12, 0.22);
      balls.add(
        Ball(
            id: _nextId++,
            tier: pending.tier,
            maxHp: pending.hp,
            x: pending.direction > 0 ? -r : width + r,
            y: flyY,
            vx: pending.direction * _clampDrift(EnemySpec.treasureSpeed),
            vy: 0,
            entering: true,
            kind: EnemyKind.treasure,
          )
          ..flyY = flyY
          ..flyPhase = _rng.range(0, math.pi * 2),
      );
      return;
    }
    if (pending.kind == EnemyKind.skyray) {
      const r = EnemySpec.skyrayRadius;
      final flyY = floorY * _rng.range(0.16, 0.3);
      balls.add(
        Ball(
            id: _nextId++,
            tier: pending.tier,
            maxHp: pending.hp,
            x: pending.direction > 0 ? -r : width + r,
            y: flyY,
            vx: pending.direction * _clampDrift(EnemySpec.skyraySpeed),
            vy: 0,
            entering: true,
            kind: EnemyKind.skyray,
            affinity: pending.affinity,
          )
          ..flyY = flyY
          ..flyPhase = _rng.range(0, math.pi * 2)
          ..dropTimer = EnemySpec.skyrayDropInterval * _rng.range(0.6, 1.0),
      );
      return;
    }
    final r = BallSpec.radius[pending.tier];
    final geode = pending.kind == EnemyKind.geode;
    balls.add(
      Ball(
        id: _nextId++,
        tier: pending.tier,
        maxHp: pending.hp,
        x: pending.x,
        y: -r,
        vx:
            pending.direction *
            _speedFor(pending.tier) *
            (geode ? EnemySpec.geodeSpeedFactor : 1) *
            pending.speedFactor,
        vy: 0,
        entering: true,
        kind: pending.kind,
        armor: pending.armor,
        affinity: pending.affinity,
      ),
    );
  }

  void _clearWave() {
    wavesCleared++;
    score += RewardSpec.waveClearBonusPerWave * wave;
    // Anything still on the floor is collected so no reward is lost.
    for (final p in pickups) {
      if (!p.collected) _collect(p);
    }
    // Leftover hazards and enemy shots fade out between waves.
    hazards.clear();
    shots.clear();
    telegraphs.clear();
    zones.clear();
    blasts.clear();
    events.add(WaveCleared(wave));
    final total = plan.waveCount;
    if (total != null && wave >= total) {
      if (chainCount > 0) _endChain();
      phase = RunPhase.stageCleared;
      bullets.clear();
      events.add(const StageCleared());
      return;
    }
    phase = RunPhase.intermission;
    intermissionTimer = WaveSpec.intermission;
  }

  /// Horizontal speed of a crystal of [tier] in the current wave. Every
  /// horizontal velocity given to a crystal goes through [_clampDrift].
  double _speedFor(int tier) => _clampDrift(BallSpec.baseSpeedX[tier] * _drift);

  static double _clampDrift(double v) =>
      v.clamp(-SpeedSpec.maxDriftSpeed, SpeedSpec.maxDriftSpeed);

  /// Launch speed that makes a ball of [tier] peak at its apex height.
  double bounceSpeed(int tier) {
    final r = BallSpec.radius[tier];
    final profile = switch (_bounce) {
      BounceProfile.normal => 1.0,
      BounceProfile.low => SpeedSpec.lowBounce,
      BounceProfile.high => SpeedSpec.highBounce,
    };
    final apexAboveFloor = math.min(
      BallSpec.apexFraction[tier] * floorY * profile,
      floorY - r * 2 - 8,
    );
    final rise = math.max(20.0, apexAboveFloor - r);
    return math.sqrt(2 * Physics.gravity * rise);
  }

  // ---------------------------------------------------------------------
  // Shooting
  // ---------------------------------------------------------------------

  double get shotInterval => 1 / loadout.shotsPerSecond;

  double get currentDamage {
    final mult = switch (element) {
      Element.kinetic => ElementSpec.kineticDamage,
      Element.fire => ElementSpec.fireDamage,
      Element.ice => ElementSpec.iceDamage,
      Element.electric => ElementSpec.electricDamage,
    };
    return loadout.damage *
        mult *
        (powerShotActive ? PowerUpSpec.powerShotMultiplier : 1);
  }

  void _fire(double h) {
    _fireTimer -= h;
    while (_fireTimer <= 0) {
      _fireTimer += shotInterval;
      final n = loadout.streams;
      final muzzleY = floorY - CannonSpec.barrelTipHeight;
      for (var i = 0; i < n; i++) {
        final offset = (i - (n - 1) / 2) * BulletSpec.streamSpacing;
        bullets.add(
          Bullet(
            cannonX + offset,
            muzzleY,
            currentDamage,
            powered: powerShotActive,
            element: element,
          ),
        );
      }
      events.add(ShotFired(element));
    }
  }

  void _updateBullets(double h) {
    final travel = BulletSpec.speed * h;
    final b = boss;
    for (final bullet in bullets) {
      if (bullet.dead) continue;
      final fromY = bullet.y;
      final toY = bullet.y - travel;
      bullet.y = toY;
      if (toY < -20) {
        bullet.dead = true;
        continue;
      }
      // Swept test along the vertical path travelled this step, so fast
      // bullets cannot skip over small targets. The first target touched
      // (lowest leading edge) takes the hit.
      Object? target;
      var targetEdge = double.negativeInfinity;
      void consider(Object t, double cx, double cy, double r) {
        final reach = r + BulletSpec.radius;
        final dx = (bullet.x - cx).abs();
        if (dx > reach) return;
        final half = math.sqrt(reach * reach - dx * dx);
        final bottom = cy + half;
        final top = cy - half;
        if (toY <= bottom && fromY >= top && bottom > targetEdge) {
          target = t;
          targetEdge = bottom;
        }
      }

      for (final ball in balls) {
        if (ball.dead || (ball.entering && ball.y + ball.radius < 0)) continue;
        consider(ball, ball.x, ball.y, ball.radius);
      }
      for (final hz in hazards) {
        if (!hz.dead) consider(hz, hz.x, hz.y, hz.radius);
      }
      for (final s in shots) {
        if (!s.dead) consider(s, s.x, s.y, s.radius);
      }
      // Bullets pass through the boss, so it can never shield its own balls.
      // A spark shows they did nothing (throttled to a few per second).
      if (b != null &&
          !b.dead &&
          b.shieldFx <= 0 &&
          _within(bullet.x, toY, b.x, b.y, b.coreRadius)) {
        b.shieldFx = 0.12;
        events.add(BossShielded(bullet.x, toY));
      }

      final hit = target;
      if (hit == null) continue;
      bullet.dead = true;
      _applyBulletHit(bullet, hit, math.min(fromY, targetEdge));
    }
  }

  void _applyBulletHit(Bullet bullet, Object hit, double hy) {
    final dmg = bullet.damage;
    final e = bullet.element;
    final hx = bullet.x;
    switch (hit) {
      case final Ball ball:
        damageBall(ball, dmg, hitY: hy, element: e);
        if (e == Element.ice) _chill(ball);
      case final Hazard hz:
        _damageHazard(hz, dmg, 0);
      case final EnemyShot s:
        s.dead = true;
        events.add(ShotDropped(s.x, s.y));
    }
    final power = loadout.elementPower;
    switch (e) {
      case Element.fire:
        final r = ElementSpec.fireSplashRadius * math.sqrt(power);
        events.add(SplashHit(hx, hy, r));
        _areaDamage(
          hx,
          hy,
          r,
          dmg * ElementSpec.fireSplashFraction * power,
          DamageSource.splash,
          exclude: hit,
          element: Element.fire,
        );
      case Element.electric:
        _arc(hx, hy, dmg * ElementSpec.arcFraction * power, exclude: hit);
      case Element.kinetic:
      case Element.ice:
        break;
    }
  }

  void _chill(Ball ball) {
    // Ice-affinity crystals cannot be chilled.
    if (ball.dead || ball.affinity == Element.ice) return;
    final power = loadout.elementPower;
    ball.chill = ElementSpec.chillDuration * power;
    ball.frostStacks++;
    if (ball.frostStacks >= ElementSpec.freezeStacks) {
      ball.frostStacks = 0;
      ball.frozen = ElementSpec.freezeDuration * power;
      events.add(EnemyFrozen(ball.x, ball.y));
    }
  }

  /// Electric arc from a hit point to the nearest other targets.
  void _arc(double x, double y, double damage, {Object? exclude}) {
    final targets = _nearestTargets(
      x,
      y,
      ElementSpec.arcRadius,
      ElementSpec.arcTargets,
      exclude: exclude,
    );
    if (targets.isEmpty) return;
    final points = [math.Point(x, y)];
    for (final t in targets) {
      points.add(math.Point(t.$2, t.$3));
      _damageTarget(t.$1, damage, DamageSource.arc, Element.electric, 0);
    }
    events.add(ArcZap(points));
  }

  /// Up to [count] creatures/hazards nearest to (x, y) within [range].
  List<(Object, double, double)> _nearestTargets(
    double x,
    double y,
    double range,
    int count, {
    Object? exclude,
  }) {
    final found = <(Object, double, double, double)>[];
    void add(Object t, double tx, double ty, double r) {
      if (identical(t, exclude)) return;
      final dx = tx - x;
      final dy = ty - y;
      final d = math.sqrt(dx * dx + dy * dy) - r;
      if (d <= range) found.add((t, tx, ty, d));
    }

    for (final b in balls) {
      if (!b.dead && !b.entering) add(b, b.x, b.y, b.radius);
    }
    for (final hz in hazards) {
      if (!hz.dead) add(hz, hz.x, hz.y, hz.radius);
    }
    found.sort((a, b) => a.$4.compareTo(b.$4));
    return [for (final f in found.take(count)) (f.$1, f.$2, f.$3)];
  }

  void _damageTarget(
    Object t,
    double damage,
    DamageSource source,
    Element element,
    int depth,
  ) {
    switch (t) {
      case final Ball ball:
        damageBall(ball, damage, source: source, element: element);
      case final Hazard hz:
        _damageHazard(hz, damage, depth);
    }
  }

  /// Damages everything in a circle (creatures and hazards).
  void _areaDamage(
    double x,
    double y,
    double radius,
    double damage,
    DamageSource source, {
    Object? exclude,
    Element element = Element.kinetic,
    int depth = 0,
  }) {
    for (final ball in List<Ball>.of(balls)) {
      if (ball.dead || identical(ball, exclude)) continue;
      if (_within(ball.x, ball.y, x, y, radius + ball.radius)) {
        damageBall(ball, damage, source: source, element: element);
      }
    }
    for (final hz in List<Hazard>.of(hazards)) {
      if (hz.dead || identical(hz, exclude)) continue;
      if (_within(hz.x, hz.y, x, y, radius + hz.radius)) {
        _damageHazard(hz, damage, depth);
      }
    }
  }

  static bool _within(double ax, double ay, double bx, double by, double r) {
    final dx = ax - bx;
    final dy = ay - by;
    return dx * dx + dy * dy <= r * r;
  }

  /// Applies damage once. Returns true if the creature was destroyed.
  bool damageBall(
    Ball ball,
    num amount, {
    DamageSource source = DamageSource.bullet,
    Element element = Element.kinetic,
    double? hitY,
    double? pushFromX,
  }) {
    if (ball.dead || amount <= 0) return false;
    var a = amount.toDouble();
    final explosive =
        source == DamageSource.blast ||
        source == DamageSource.splash ||
        source == DamageSource.bomb;
    if (ball.isFrozen && (explosive || element == Element.fire)) {
      a *= ElementSpec.shatterBonus;
    }
    // Bombs ignore affinities; everything else checks the element.
    if (source != DamageSource.bomb) {
      a *= Affinity.multiplier(ball.affinity, element);
    }
    ball.hitFlash = BallSpec.hitFlashTime;
    final hy = hitY ?? ball.y + ball.radius;
    if (ball.armored) {
      final shell =
          a *
          (element == Element.fire || explosive ? ElementSpec.fireVsArmor : 1);
      final dealt = math.min(shell, ball.armor);
      ball.armor -= shell;
      _addScore(dealt);
      events.add(BallHit(ball.x, hy, ball.tier, armored: true));
      if (ball.armor <= 1e-9) {
        ball.armor = 0;
        events.add(ArmorBroken(ball.x, ball.y, ball.radius));
        for (var i = 0; i < EnemySpec.geodeArmorBreakCoins; i++) {
          _spawnCoin(ball.x, ball.y, 1);
        }
      }
      return false;
    }
    final dealt = math.min(a, ball.hp);
    ball.hp -= a;
    _addScore(dealt);
    if (source == DamageSource.bullet) {
      events.add(BallHit(ball.x, hy, ball.tier));
    }
    if (ball.hp <= 1e-9) {
      ball.hp = 0;
      _destroyBall(ball, source: source, pushFromX: pushFromX);
      return true;
    }
    return false;
  }

  void _addScore(double points) {
    _scoreRemainder += points * RewardSpec.scorePerDamage;
    final whole = _scoreRemainder.floor();
    _scoreRemainder -= whole;
    score += whole;
  }

  void _destroyBall(
    Ball ball, {
    required DamageSource source,
    double? pushFromX,
  }) {
    // `dead` is the single guard that makes splitting and rewards happen
    // exactly once even if several hits land in the same step.
    if (ball.dead) return;
    ball.dead = true;
    ballsDestroyed++;
    score += RewardSpec.destroyBonusPerTier * (ball.tier + 1);
    if (source != DamageSource.bullet) _chainTick();

    final split = ball.tier > 0 && !ball.isFlyer;
    if (split) _split(ball, pushFromX: pushFromX);
    if (ball.isTreasure) {
      for (var i = 0; i < EnemySpec.treasureCoins; i++) {
        _spawnCoin(ball.x, ball.y, 2);
      }
    } else if (ball.isFlyer) {
      for (var i = 0; i < EnemySpec.skyrayCoins; i++) {
        _spawnCoin(ball.x, ball.y, 1);
      }
    } else {
      _maybeDrop(ball);
    }
    events.add(
      BallDestroyed(ball.x, ball.y, ball.tier, split: split, kind: ball.kind),
    );
    _bossLosesBall();
  }

  void _split(Ball parent, {double? pushFromX}) {
    final tier = parent.tier - 1;
    final hp = math.max(1, (parent.maxHp * BallSpec.childHpRatio).round());
    final r = BallSpec.radius[tier];
    final speed = _speedFor(tier);
    final pop = -math.sqrt(2 * Physics.gravity * BallSpec.splitPopHeight);
    for (final dir in const [-1, 1]) {
      var vx = dir * speed;
      if (pushFromX != null) {
        // Bomb blasts throw both children away from the cannon.
        final away = (parent.x + dir * r * 0.5 - pushFromX).sign;
        vx = _clampDrift((away == 0 ? dir.toDouble() : away) * speed * 1.4);
      }
      _newBalls.add(
        Ball(
          id: _nextId++,
          tier: tier,
          maxHp: hp,
          x: (parent.x + dir * r * 0.6).clamp(r, width - r),
          y: math.min(parent.y, floorY - r),
          vx: vx,
          vy: pop,
          affinity: parent.affinity,
        ),
      );
    }
  }

  void _maybeDrop(Ball ball) {
    final roll = _rng.nextDouble();
    if (roll < RewardSpec.powerUpDropChance &&
        !pickups.any((p) => p.kind == PickupKind.powerUp)) {
      final type = PowerUpType.values[_rng.nextInt(PowerUpType.values.length)];
      pickups.add(
        Pickup(
          kind: PickupKind.powerUp,
          x: ball.x,
          y: ball.y,
          vx: 0,
          vy: -180,
          life: RewardSpec.powerUpLifetime,
          powerUp: type,
        ),
      );
      return;
    }
    if (_rng.nextDouble() < RewardSpec.coinDropChance) {
      _spawnCoin(ball.x, ball.y, RewardSpec.coinValue[ball.tier]);
    }
  }

  void _spawnCoin(double x, double y, int value) {
    final activeCoins = pickups.where((p) => p.kind == PickupKind.coin);
    if (activeCoins.length >= RewardSpec.maxActiveCoins) {
      // Too many coins on screen: credit directly rather than spawning.
      _awardCoins(value, x, y);
      return;
    }
    pickups.add(
      Pickup(
        kind: PickupKind.coin,
        x: x,
        y: y,
        vx: _rng.range(-40, 40),
        vy: -_rng.range(140, 240),
        life: RewardSpec.coinLifetime,
        value: value,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Hazards, blasts and chains
  // ---------------------------------------------------------------------

  void _damageHazard(Hazard hz, double amount, int depth) {
    if (hz.dead || amount <= 0) return;
    hz.hp -= amount;
    hz.hitFlash = BallSpec.hitFlashTime;
    events.add(HazardHit(hz.x, hz.y, hz.kind));
    if (hz.hp > 0) return;
    hz.dead = true;
    final damageFactor = switch (hz.kind) {
      HazardKind.blaze => HazardSpec.blazeDamageFactor,
      HazardKind.frost => HazardSpec.frostDamageFactor,
      HazardKind.storm => HazardSpec.stormDamageFactor,
    };
    // Detonations triggered by other detonations wait a beat so a chain
    // reads as a sequence.
    blasts.add(
      Blast(
        kind: hz.kind,
        x: hz.x,
        y: hz.y,
        damage: scale * damageFactor * loadout.elementPower,
        delay: depth == 0 ? 0 : HazardSpec.chainDelay,
        depth: depth + 1,
      ),
    );
  }

  void _processBlasts(double h) {
    if (blasts.isEmpty) return;
    final ready = <Blast>[];
    for (final b in blasts) {
      b.delay -= h;
      if (b.delay <= 0) ready.add(b);
    }
    blasts.removeWhere((b) => b.delay <= 0);
    for (final b in ready) {
      _chainTick();
      switch (b.kind) {
        case HazardKind.blaze:
          events.add(
            HazardDetonated(b.kind, b.x, b.y, HazardSpec.blazeRadius, b.depth),
          );
          _areaDamage(
            b.x,
            b.y,
            HazardSpec.blazeRadius,
            b.damage,
            DamageSource.blast,
            element: Element.fire,
            depth: b.depth,
          );
        case HazardKind.frost:
          events.add(
            HazardDetonated(b.kind, b.x, b.y, HazardSpec.frostRadius, b.depth),
          );
          for (final ball in balls) {
            if (!ball.dead &&
                _within(
                  ball.x,
                  ball.y,
                  b.x,
                  b.y,
                  HazardSpec.frostRadius + ball.radius,
                )) {
              ball.frozen = math.max(ball.frozen, HazardSpec.frostFreeze);
              events.add(EnemyFrozen(ball.x, ball.y));
            }
          }
          _areaDamage(
            b.x,
            b.y,
            HazardSpec.frostRadius,
            b.damage,
            DamageSource.frost,
            element: Element.ice,
            depth: b.depth,
          );
        case HazardKind.storm:
          events.add(
            HazardDetonated(b.kind, b.x, b.y, HazardSpec.stormRange, b.depth),
          );
          final targets = _nearestTargets(
            b.x,
            b.y,
            HazardSpec.stormRange,
            HazardSpec.stormTargets,
          );
          for (final t in targets) {
            events.add(ArcZap([math.Point(b.x, b.y), math.Point(t.$2, t.$3)]));
            _damageTarget(
              t.$1,
              b.damage,
              DamageSource.blast,
              Element.electric,
              b.depth,
            );
          }
      }
    }
  }

  void _chainTick() {
    chainCount++;
    chainTimer = ChainSpec.window;
    if (chainCount > bestChain) bestChain = chainCount;
    if (chainCount >= 2) events.add(ChainProgress(chainCount));
  }

  void _endChain() {
    final count = chainCount;
    chainCount = 0;
    chainTimer = 0;
    if (count < ChainSpec.minForBonus) return;
    score += ChainSpec.scorePerSquare * count * count;
    final before = coins;
    _awardCoins(count, cannonX, floorY - 60, emit: false);
    events.add(ChainEnded(count, coins - before));
  }

  // ---------------------------------------------------------------------
  // Creature motion
  // ---------------------------------------------------------------------

  void _updateBalls(double h) {
    final world = h * ballTimeScale;
    for (final ball in balls) {
      if (ball.dead) continue;
      if (ball.hitFlash > 0) ball.hitFlash = math.max(0, ball.hitFlash - h);
      if (ball.squash > 0) ball.squash = math.max(0, ball.squash - h);
      if (ball.chill > 0) ball.chill = math.max(0, ball.chill - h);
      if (ball.frozen > 0) {
        ball.frozen = math.max(0, ball.frozen - h);
        continue; // encased in ice: no movement at all
      }
      final t = world * ball.moveScale;
      if (ball.isFlyer) {
        _updateFlyer(ball, t);
        continue;
      }

      ball.vy += Physics.gravity * t;
      ball.x += ball.vx * t;
      ball.y += ball.vy * t;
      final r = ball.radius;

      // Recover from any numerical blow-up instead of losing the ball.
      if (!ball.x.isFinite || !ball.y.isFinite) {
        ball
          ..x = width / 2
          ..y = r
          ..vx = _speedFor(ball.tier)
          ..vy = 0;
      }

      if (ball.y + r >= floorY) {
        ball.y = floorY - r;
        ball.vy = -bounceSpeed(ball.tier);
        ball.squash = BallSpec.squashTime;
        events.add(BallBounced(ball.x, ball.tier));
      }
      if (ball.x - r < 0) {
        ball.x = r;
        ball.vx = ball.vx.abs();
      } else if (ball.x + r > width) {
        ball.x = width - r;
        ball.vx = -ball.vx.abs();
      }
      if (ball.entering) {
        if (ball.y - r >= 0) ball.entering = false;
      } else if (ball.y - r < 0) {
        ball.y = r;
        ball.vy = ball.vy.abs();
      }
    }
  }

  void _updateFlyer(Ball ray, double t) {
    final r = ray.radius;
    ray.x += ray.vx * t;
    ray.flyPhase += t * 2.2;
    ray.y = ray.flyY + math.sin(ray.flyPhase) * EnemySpec.skyrayBobAmplitude;
    if (ray.isTreasure) {
      // Treasure crosses once and leaves through the far side.
      if (ray.entering) {
        if (ray.x - r >= 0 && ray.x + r <= width) ray.entering = false;
      } else if (ray.x < -r || ray.x > width + r) {
        ray.dead = true;
        events.add(TreasureEscaped(ray.x.clamp(0, width), ray.y));
      }
      return;
    }
    if (ray.entering) {
      if (ray.x - r >= 0 && ray.x + r <= width) ray.entering = false;
    } else if (ray.x - r < 0) {
      ray.x = r;
      ray.vx = ray.vx.abs();
    } else if (ray.x + r > width) {
      ray.x = width - r;
      ray.vx = -ray.vx.abs();
    }
    if (ray.entering) return;
    ray.dropTimer -= t;
    if (ray.dropTimer <= 0) {
      ray.dropTimer =
          math.max(1.6, EnemySpec.skyrayDropInterval - difficulty * 0.05) *
          _rng.range(0.8, 1.2);
      shots.add(
        EnemyShot(ray.x, ray.y + r, ray.vx * 0.2, EnemySpec.shotSpeed * 0.4),
      );
    }
  }

  void _updateShots(double h) {
    final t = h * ballTimeScale;
    for (final s in shots) {
      if (s.dead) continue;
      s.vy += EnemySpec.shotGravity * t;
      s.x += s.vx * t;
      if (s.weave != 0) {
        // Bounded sideways swing: x offset follows weave * sin(phase).
        final before = math.sin(s.weavePhase);
        s.weavePhase += t * 2.4;
        s.x += s.weave * (math.sin(s.weavePhase) - before);
      }
      s.y += s.vy * t;
      if (s.x < s.radius || s.x > width - s.radius) s.vx = -s.vx;
      if (s.y + s.radius >= floorY) {
        s.dead = true;
        events.add(ShotDropped(s.x, floorY));
        continue;
      }
      if (_overlapsCannonCircle(s.x, s.y, s.radius)) {
        s.dead = true;
        _hurtPlayer();
      }
    }
  }

  void _updateTelegraphs(double h) {
    for (final tg in telegraphs) {
      tg.timer -= h;
      if (tg.timer > 0) continue;
      switch (tg.kind) {
        case TelegraphKind.rain:
          shots.add(EnemyShot(tg.x, -10, 0, EnemySpec.shotSpeed));
        case TelegraphKind.zap:
          final reach = tg.width + CannonSpec.bodyHalfWidth - 6;
          final hit = (cannonX - tg.x).abs() < reach;
          events.add(ZapStrike(tg.x, tg.width, hit: hit));
          if (hit) _hurtPlayer();
        case TelegraphKind.slam:
          break;
      }
    }
    telegraphs.removeWhere((t) => t.timer <= 0);
  }

  void _updateZones(double h) {
    for (final z in zones) {
      if (!z.armed) {
        z.warning -= h;
        if (z.armed) {
          events.add(ZoneArmed(z.kind, z.x, z.halfWidth));
          if (z.kind == ZoneKind.freeze && _cannonInZone(z)) {
            z.spent = true;
            cannonSlowTimer = BossSpec.freezeSlowTime;
            events.add(CannonChilled(cannonX, floorY - 30));
          }
        }
        continue;
      }
      z.active -= h;
      if (z.kind == ZoneKind.lava && !z.spent && _cannonInZone(z)) {
        if (invulnerableTimer <= 0 && !isFinished) {
          z.spent = true;
          _hurtPlayer();
        }
      }
    }
    zones.removeWhere((z) => z.done);
  }

  bool _cannonInZone(FloorZone z) =>
      (cannonX - z.x).abs() < z.halfWidth + CannonSpec.bodyHalfWidth * 0.5;

  // ---------------------------------------------------------------------
  // Boss
  // ---------------------------------------------------------------------

  void _updateBoss(double h) {
    final b = boss;
    if (b == null || b.dead) return;
    if (b.hitFlash > 0) b.hitFlash = math.max(0, b.hitFlash - h);
    if (b.shieldFx > 0) b.shieldFx = math.max(0, b.shieldFx - h);
    if (b.throwRecoil > 0) b.throwRecoil = math.max(0, b.throwRecoil - h);
    final t = h * ballTimeScale;

    // The last ball is gone: the boss goes down with its supply.
    if (b.ballQueue.isEmpty &&
        _newBalls.isEmpty &&
        balls.every((ball) => ball.dead)) {
      _defeatBoss(b);
      return;
    }

    // Movement (unless slamming). During the entrance the boss glides down
    // from above the arena to its hover height.
    if (b.slam == SlamState.none) {
      b.x += b.dir * b.speed * t;
      final margin = b.def.margin;
      if (b.x < margin) {
        b.x = margin;
        b.dir = 1;
      } else if (b.x > width - margin) {
        b.x = width - margin;
        b.dir = -1;
      }
      b.y += (b.homeY - b.y) * math.min(1, t * 3);
    }

    if (b.transition > 0) {
      b.transition = math.max(0, b.transition - h);
      // Finish a slam the phase change interrupted, so the boss never sits
      // on the floor for the whole transition.
      if (b.slam == SlamState.rising) _rise(b, t);
      return;
    }

    // It keeps throwing whatever else it is doing, a slam included.
    _updateThrowing(b, t);
    if (b.slam != SlamState.none) {
      _updateSlam(b, t);
      return;
    }

    // Each attack of the phase has its own timer; [BossSpec.attackGap]
    // keeps two attacks from starting together.
    if (b.attackGap > 0) b.attackGap = math.max(0, b.attackGap - t);
    for (final a in b.phaseDef.attacks) {
      final left = (b.timers[a] ?? b.interval(a)) - t;
      b.timers[a] = left;
      if (left > 0 || b.attackGap > 0) continue;
      if (_startAttack(b, a)) {
        b.timers[a] = b.interval(a) * _rng.range(0.85, 1.15);
        b.attackGap = BossSpec.attackGap;
      } else {
        // Not possible right now (e.g. minion cap): retry shortly.
        b.timers[a] = 1.0;
      }
      break;
    }
  }

  void _updateThrowing(Boss b, double t) {
    if (b.ballQueue.isEmpty) return;
    b.throwTimer -= t;
    if (b.throwTimer > 0) return;
    // A full arena just delays the throw: the supply never shrinks by itself.
    if (balls.length + _newBalls.length >= BossSpec.maxThrownAlive) {
      b.throwTimer = 0;
      return;
    }
    _throwBall(b, b.x);
    b.throwTimer = b.currentThrowInterval * _rng.range(0.85, 1.15);
  }

  /// Throws the next ball of the boss's supply from above [fromX].
  void _throwBall(Boss b, double fromX) {
    final tier = b.ballQueue.removeAt(0);
    final r = BallSpec.radius[tier];
    final hp = math.max(1, (scale * WaveSpec.tierHpFactor[tier]).round());
    // Armour needs a shell-sized body.
    final geode = b.def.minionKind == EnemyKind.geode && tier >= 2;
    final affinity = b.def.minionAffinity
        ? const [Element.fire, Element.ice, Element.electric][_rng.nextInt(3)]
        : null;
    // Mostly at the cannon, so standing still is never safe.
    final towards = (cannonX - fromX) >= 0 ? 1.0 : -1.0;
    final dir = _rng.nextDouble() < BossSpec.throwAtCannonChance
        ? towards
        : -towards;
    final y = b.y + b.coreRadius;
    _newBalls.add(
      Ball(
        id: _nextId++,
        tier: tier,
        maxHp: hp,
        x: fromX.clamp(r, width - r),
        y: y,
        vx: dir * _speedFor(tier),
        vy: BossSpec.throwVelocity,
        kind: geode ? EnemyKind.geode : EnemyKind.shard,
        armor: geode ? (hp * EnemySpec.geodeArmorFraction).roundToDouble() : 0,
        affinity: affinity,
      ),
    );
    b.throwRecoil = BossSpec.throwRecoilTime;
    events.add(BossThrew(fromX, y));
  }

  /// A ball of the boss's supply, or a piece of one, was destroyed.
  void _bossLosesBall() {
    final b = boss;
    if (b == null || b.dead) return;
    b.unitsLeft = math.max(0, b.unitsLeft - 1);
    b.hitFlash = BallSpec.hitFlashTime;
    events.add(BossHit(b.x, b.y + b.coreRadius * 0.6, plate: false));

    // Armour falls off evenly as health drops.
    final lost = 1 - b.coreFraction;
    for (var i = 0; i < b.plates.length; i++) {
      if (b.plates[i] > 0 && lost >= (i + 1) / (b.plates.length + 1)) {
        b.plates[i] = 0;
        events.add(BossPlateBroken(b.plateX(i), b.plateY(i)));
        for (var c = 0; c < 4; c++) {
          _spawnCoin(b.plateX(i), b.plateY(i), 1);
        }
      }
    }

    if (b.targetPhase > b.phase && b.unitsLeft > 0) _nextBossPhase(b);
  }

  void _nextBossPhase(Boss b) {
    final next = b.phase + 1;
    b.phase = next;
    b.transition = BossSpec.phaseTransition;
    if (b.slam != SlamState.none) b.slam = SlamState.rising;
    // An interrupted slam must not hurt the player on its way back up.
    b.slamHit = true;
    b.armPhase();
    telegraphs.removeWhere((t) => t.slam);
    events.add(BossPhaseChanged(next));
    // Fresh volatile crystals beside the boss reward chain-reaction play.
    final kinds = switch (plan) {
      final StagePlan p => p.level.hazardKinds,
      _ => const [HazardKind.blaze],
    };
    if (kinds.isNotEmpty && hazards.where((h) => !h.dead).length < 2) {
      for (final (k, xf) in [(0, 0.22), (1, 0.78)]) {
        hazards.add(
          Hazard(
            id: _nextId++,
            kind: kinds[(k + next) % kinds.length],
            x: xf * width,
            y: b.homeY + b.coreRadius + 35,
            maxHp: _hazardHp,
          ),
        );
      }
    }
  }

  /// Starts [attack]. Returns false if it could not start now.
  bool _startAttack(Boss b, BossAttack attack) {
    // Fairness: a frosted cannon steers slowly, so attacks aimed at it wait
    // until it can move freely again.
    if (cannonSlowed &&
        (attack == BossAttack.slam ||
            attack == BossAttack.zap ||
            attack == BossAttack.lava)) {
      return false;
    }
    final late = b.phase >= 3;
    switch (attack) {
      case BossAttack.rain:
        // Three telegraphed columns, one aimed at the cannon, spaced so a
        // safe band for the cannon always remains between them.
        const reach = EnemySpec.shotRadius + CannonSpec.bodyHalfWidth;
        final xs = _spacedColumns(
          cannonX.clamp(12.0, width - 12),
          3,
          minGap: reach * 2 + 40,
          edge: 12,
        );
        for (final x in xs) {
          telegraphs.add(
            Telegraph(x, BossSpec.rainTelegraph, BossSpec.rainTelegraph),
          );
        }
      case BossAttack.slam:
        b.slam = SlamState.aiming;
        b.slamX = cannonX.clamp(b.coreRadius, width - b.coreRadius);
        b.slamTimerLeft = BossSpec.slamTelegraph;
        b.slamHit = false;
        telegraphs.add(
          Telegraph(
            b.slamX,
            BossSpec.slamTelegraph,
            BossSpec.slamTelegraph,
            slam: true,
            width: b.coreRadius,
          ),
        );
      case BossAttack.minions:
        // A burst: two balls of its supply at once, from either side.
        if (b.ballQueue.length < 2 ||
            balls.length + _newBalls.length + 2 > BossSpec.maxThrownAlive) {
          return false;
        }
        _throwBall(b, b.x - 30);
        _throwBall(b, b.x + 30);
      case BossAttack.fan:
        // Five shards fanned out (three per head for heads that fire).
        final sources = <(double, double)>[
          if (b.def.headsFire)
            for (var i = 0; i < b.plates.length; i++)
              if (b.plates[i] > 0)
                (b.plateX(i), b.plateY(i) + b.plateRadius(i)),
        ];
        if (sources.isEmpty) {
          for (var i = -2; i <= 2; i++) {
            shots.add(EnemyShot(b.x, b.y + b.coreRadius, i * 55.0, 120));
          }
          events.add(ShotDropped(b.x, b.y + b.coreRadius));
        } else {
          // Each head spits one shard angled towards the cannon.
          for (final (sx, sy) in sources) {
            final aim = ((cannonX - sx) * 0.35).clamp(-70.0, 70.0);
            shots.add(EnemyShot(sx, sy, aim, 115));
            events.add(ShotDropped(sx, sy));
          }
        }
      case BossAttack.zap:
        // One column on the cannon and one or two elsewhere, spaced so a
        // gap wide enough for the cannon always remains between them.
        const reach = BossSpec.zapHalfWidth + CannonSpec.bodyHalfWidth;
        final xs = _spacedColumns(
          cannonX.clamp(BossSpec.zapHalfWidth, width - BossSpec.zapHalfWidth),
          late ? 3 : 2,
          minGap: reach * 2 + CannonSpec.bodyHalfWidth * 2 + 16,
          edge: BossSpec.zapHalfWidth,
        );
        for (final x in xs) {
          telegraphs.add(
            Telegraph(
              x,
              BossSpec.zapTelegraph,
              BossSpec.zapTelegraph,
              kind: TelegraphKind.zap,
              width: BossSpec.zapHalfWidth,
            ),
          );
        }
      case BossAttack.lava:
        // One pool under the cannon; in later phases a second one on the
        // far half of the arena, so there is always dry ground in between.
        const half = BossSpec.lavaHalfWidth;
        final first = cannonX.clamp(half, width - half);
        final xs = [
          first,
          if (b.phase >= 2) first < width / 2 ? width - half - 6 : half + 6,
        ];
        for (final x in xs) {
          zones.add(
            FloorZone(
              kind: ZoneKind.lava,
              x: x,
              halfWidth: BossSpec.lavaHalfWidth,
              warning: BossSpec.lavaTelegraph,
              active: BossSpec.lavaDuration,
            ),
          );
        }
      case BossAttack.freeze:
        zones.add(
          FloorZone(
            kind: ZoneKind.freeze,
            x: cannonX.clamp(
              BossSpec.freezeHalfWidth,
              width - BossSpec.freezeHalfWidth,
            ),
            halfWidth: BossSpec.freezeHalfWidth,
            warning: BossSpec.freezeTelegraph,
            active: 1.2,
          ),
        );
      case BossAttack.curve:
        for (var i = -1; i <= 1; i++) {
          shots.add(
            EnemyShot(
              b.x + i * 26,
              b.y + b.coreRadius,
              i * 30.0,
              95,
              weave: BossSpec.curveAmplitude * (i == 0 ? 1 : -1),
            ),
          );
        }
        events.add(ShotDropped(b.x, b.y + b.coreRadius));
      case BossAttack.pull:
        var pulled = 0;
        for (final ball in balls) {
          if (ball.dead || ball.isFlyer) continue;
          // Direction only: speed is unchanged, so this can never create a
          // faster crystal.
          final dir = (b.x - ball.x).sign;
          if (dir != 0) ball.vx = dir * ball.vx.abs();
          pulled++;
        }
        if (pulled == 0) return false;
        events.add(BossPulled(b.x, b.y));
    }
    return true;
  }

  /// [count] column positions starting with [first], every pair at least
  /// [minGap] apart and [edge] away from the walls (fewer if they do not
  /// fit).
  List<double> _spacedColumns(
    double first,
    int count, {
    required double minGap,
    required double edge,
  }) {
    final xs = [first];
    for (var tries = 0; xs.length < count && tries < 24; tries++) {
      final x = _rng.range(edge, width - edge);
      if (xs.every((o) => (o - x).abs() >= minGap)) xs.add(x);
    }
    return xs;
  }

  void _updateSlam(Boss b, double t) {
    switch (b.slam) {
      case SlamState.none:
        break;
      case SlamState.aiming:
        b.x += (b.slamX - b.x) * math.min(1, t * 4);
        b.slamTimerLeft -= t;
        if (b.slamTimerLeft <= 0) b.slam = SlamState.diving;
      case SlamState.diving:
        b.y += BossSpec.slamSpeed * t;
        if (b.y + b.coreRadius >= floorY) {
          b.y = floorY - b.coreRadius;
          b.slam = SlamState.rising;
          events.add(BallBounced(b.x, 4));
        }
        _slamContact(b);
      case SlamState.rising:
        _slamContact(b);
        _rise(b, t);
    }
  }

  void _rise(Boss b, double t) {
    b.y -= BossSpec.slamSpeed * 0.45 * t;
    if (b.y <= b.homeY) {
      b.y = b.homeY;
      b.slam = SlamState.none;
    }
  }

  void _slamContact(Boss b) {
    if (b.slamHit) return;
    if (_overlapsCannonCircle(b.x, b.y, b.coreRadius * 0.9)) {
      b.slamHit = true;
      _hurtPlayer();
    }
  }

  void _defeatBoss(Boss b) {
    b.unitsLeft = 0;
    b.dead = true;
    bossDefeated = true;
    score += 2000;
    events.add(BossDefeated(b.x, b.y));
    for (var i = 0; i < BossSpec.defeatCoins ~/ 4; i++) {
      _spawnCoin(b.x + _rng.range(-40, 40), b.y, 4);
    }
    // Minions shatter with their master.
    for (final ball in List<Ball>.of(balls)) {
      if (!ball.dead) {
        ball.dead = true;
        ballsDestroyed++;
        events.add(BallDestroyed(ball.x, ball.y, ball.tier, split: false));
      }
    }
    _newBalls.clear();
    shots.clear();
    telegraphs.clear();
    zones.clear();
    _spawnQueue.clear();
    pendingSpawns.clear();
    cannonSlowTimer = 0;
  }

  // ---------------------------------------------------------------------
  // Pickups
  // ---------------------------------------------------------------------

  void _updatePickups(double h) {
    final restY = floorY - 8;
    for (final p in pickups) {
      if (p.collected) continue;
      p.life -= h;
      if (!p.grounded) {
        p.vy += Physics.gravity * h;
        p.x = (p.x + p.vx * h).clamp(8, width - 8);
        p.y += p.vy * h;
        if (p.y >= restY) {
          p
            ..y = restY
            ..vx = 0
            ..vy = 0
            ..grounded = true;
        }
      }
      final nearCannon =
          (p.x - cannonX).abs() <= CannonSpec.coinPickupHalfWidth &&
          p.y >= floorY - CannonSpec.barrelTipHeight - 10;
      if (nearCannon) _collect(p);
    }
  }

  void _collect(Pickup p) {
    if (p.collected) return;
    p.collected = true;
    switch (p.kind) {
      case PickupKind.coin:
        _awardCoins(p.value, p.x, p.y);
      case PickupKind.powerUp:
        final type = p.powerUp!;
        inventory[type] = math.min(
          PowerUpSpec.maxInventory,
          inventory[type]! + 1,
        );
        events.add(PowerUpCollected(type));
    }
  }

  void _awardCoins(int base, double x, double y, {bool emit = true}) {
    // Fractional bonus is carried over so a 10% bonus is exact over time.
    _coinRemainder += base * loadout.coinMultiplier * coinScale;
    final whole = _coinRemainder.floor();
    _coinRemainder -= whole;
    coins += whole;
    if (emit) events.add(CoinCollected(x, y, whole));
  }

  // ---------------------------------------------------------------------
  // Player collision
  // ---------------------------------------------------------------------

  bool _overlapsCannonCircle(double x, double y, double r) {
    const f = CannonSpec.hitboxForgiveness;
    final left = cannonX - CannonSpec.bodyHalfWidth + f;
    final right = cannonX + CannonSpec.bodyHalfWidth - f;
    final top = floorY - CannonSpec.bodyHeight + f;
    final bottom = floorY;
    final nearestX = x.clamp(left, right);
    final nearestY = y.clamp(top, bottom);
    final dx = x - nearestX;
    final dy = y - nearestY;
    if (dx * dx + dy * dy < r * r) return true;

    final tipY = floorY - CannonSpec.barrelTipHeight + CannonSpec.barrelRadius;
    const tipR = CannonSpec.barrelRadius - f;
    final tx = x - cannonX;
    final ty = y - tipY;
    final reach = r + tipR;
    return tx * tx + ty * ty < reach * reach;
  }

  /// True if [ball] overlaps the cannon's (slightly forgiving) hitbox.
  bool overlapsCannon(Ball ball) =>
      _overlapsCannonCircle(ball.x, ball.y, ball.radius);

  void _checkCannonCollision() {
    if (invulnerableTimer > 0) return;
    for (final ball in balls) {
      if (ball.dead || !overlapsCannon(ball)) continue;
      _knockAway(ball);
      _hurtPlayer();
      return;
    }
  }

  /// One hit: the shield absorbs it, otherwise the hull loses a point.
  void _hurtPlayer() {
    if (invulnerableTimer > 0 || isFinished) return;
    final hy = floorY - CannonSpec.bodyHeight / 2;
    if (shieldActive) {
      shieldTimer = 0;
      invulnerableTimer = PowerUpSpec.shieldBreakInvulnerability;
      events.add(ShieldBroken(cannonX, floorY - CannonSpec.bodyHeight));
      return;
    }
    hull--;
    hullLost++;
    if (hull <= 0) {
      hull = 0;
      phase = RunPhase.gameOver;
      bullets.clear();
      if (chainCount > 0) _endChain();
      events.add(PlayerDestroyed(cannonX, hy));
      return;
    }
    invulnerableTimer = PlayerSpec.hurtInvulnerability;
    for (final b in balls) {
      if (!b.dead && !b.isFlyer && (b.x - cannonX).abs() < 110) _knockAway(b);
    }
    events.add(PlayerHurt(cannonX, hy, hull));
  }

  void _knockAway(Ball ball) {
    if (ball.isFlyer) return;
    final dir = ball.x >= cannonX ? 1.0 : -1.0;
    ball
      ..frozen = 0
      ..vx = dir * ball.vx.abs().clamp(60, SpeedSpec.maxDriftSpeed)
      ..vy = -bounceSpeed(ball.tier);
  }

  void _cleanup() {
    bullets.removeWhere((b) => b.dead);
    balls.removeWhere((b) => b.dead);
    if (_newBalls.isNotEmpty) {
      balls.addAll(_newBalls);
      _newBalls.clear();
    }
    hazards.removeWhere((hz) => hz.dead);
    shots.removeWhere((s) => s.dead);
    pickups.removeWhere((p) => p.collected || p.life <= 0);
  }

  // ---------------------------------------------------------------------
  // Power-ups and revive
  // ---------------------------------------------------------------------

  bool isPowerUpActive(PowerUpType type) => switch (type) {
    PowerUpType.bomb => false,
    PowerUpType.slowMotion => slowActive,
    PowerUpType.shield => shieldActive,
    PowerUpType.powerShot => powerShotActive,
  };

  bool canActivate(PowerUpType type) =>
      !isFinished &&
      (inventory[type] ?? 0) > 0 &&
      cooldownTimer <= 0 &&
      !isPowerUpActive(type);

  bool activatePowerUp(PowerUpType type) {
    if (!canActivate(type)) return false;
    inventory[type] = inventory[type]! - 1;
    cooldownTimer = PowerUpSpec.globalCooldown;
    powerUpsUsed++;
    final fx = cannonX;
    var fy = floorY - CannonSpec.bodyHeight;
    switch (type) {
      case PowerUpType.bomb:
        fy = floorY - PowerUpSpec.bombHeight;
        _detonateBomb(cannonX, fy);
      case PowerUpType.slowMotion:
        slowTimer = PowerUpSpec.slowMotionDuration;
      case PowerUpType.shield:
        shieldTimer = PowerUpSpec.shieldDuration;
      case PowerUpType.powerShot:
        powerShotTimer = PowerUpSpec.powerShotDuration;
    }
    events.add(PowerUpActivated(type, fx, fy));
    _cleanup();
    return true;
  }

  void _detonateBomb(double cx, double cy) {
    invulnerableTimer = math.max(
      invulnerableTimer,
      PowerUpSpec.bombInvulnerability,
    );
    const radius = PowerUpSpec.bombRadius;
    for (final ball in List<Ball>.of(balls)) {
      if (ball.dead) continue;
      if (_within(ball.x, ball.y, cx, cy, radius + ball.radius)) {
        ball.armor = 0;
        damageBall(ball, ball.hp, source: DamageSource.bomb, pushFromX: cx);
      }
    }
    for (final hz in List<Hazard>.of(hazards)) {
      if (!hz.dead && _within(hz.x, hz.y, cx, cy, radius + hz.radius)) {
        _damageHazard(hz, hz.hp, 0);
      }
    }
    shots.clear();
  }

  /// Continues a finished run once (after a rewarded ad). Enemies are thrown
  /// away from the cannon and the player gets hull back and invulnerability.
  bool revive() {
    if (!isOver || revived) return false;
    revived = true;
    hull = PlayerSpec.reviveHull;
    // Always resume the wave. If its last enemy died in the step that ended
    // the run, the next step clears it normally: the clear is credited,
    // leftovers are removed and a final wave ends the stage instead of
    // starting a wave past the end of the plan.
    phase = RunPhase.playing;
    invulnerableTimer = PowerUpSpec.reviveInvulnerability;
    for (final ball in balls) {
      _knockAway(ball);
    }
    shots.clear();
    telegraphs.clear();
    zones.clear();
    cannonSlowTimer = 0;
    final b = boss;
    if (b != null && b.slam != SlamState.none) {
      b.slam = SlamState.rising;
      b.slamHit = true;
    }
    _accumulator = 0;
    return true;
  }
}

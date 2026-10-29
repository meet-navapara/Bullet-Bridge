import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../progress/save_data.dart';

enum Sfx {
  shoot,
  hit,
  pop,
  coin,
  upgrade,
  powerup,
  shield,
  bomb,
  gameover,
  wave,
  click,
  explode,
  freeze,
  zap,
  armor,
  roar,
  hurt,
  stageclear,
  chain,
}

/// One preloaded sound-effect player.
abstract class SfxVoice {
  /// Restarts the sound from the beginning at [volume].
  Future<void> play(double volume);
  Future<void> dispose();
}

/// Low-latency platform player (Android SoundPool) for one effect.
///
/// `AudioPool` is not used: in low-latency mode it never hears that a sound
/// finished, so it never gets its players back and creates a new native
/// player for every play. Over a session that leaked thousands of players,
/// flooded the platform channel and eventually broke audio and frame pacing.
class _PlayerVoice implements SfxVoice {
  _PlayerVoice(this._player);

  static Future<_PlayerVoice> load(String asset) async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(AssetSource(asset));
    return _PlayerVoice(player);
  }

  final AudioPlayer _player;

  @override
  Future<void> play(double volume) async {
    // A finished low-latency stream is never reported, so it must be
    // stopped explicitly before it can play again.
    await _player.stop();
    await _player.setVolume(volume);
    await _player.resume();
  }

  @override
  Future<void> dispose() => _player.dispose();
}

typedef SfxVoiceLoader = Future<SfxVoice> Function(Sfx sfx);

/// Sound effects and music. Every call is fire-and-forget and failures are
/// swallowed: audio problems must never crash or stall the game.
class AudioService {
  AudioService({this.enabled = true, this._voiceLoader});

  /// A service that never touches the platform (tests, unsupported hosts).
  AudioService.silent() : enabled = false, _voiceLoader = null;

  final bool enabled;
  final SfxVoiceLoader? _voiceLoader;

  /// A fixed set of voices per effect, reused round-robin, so the number of
  /// native players never grows however long the game runs.
  final Map<Sfx, List<SfxVoice>> _voices = {};
  final Map<Sfx, int> _nextVoice = {};
  final Map<Sfx, int> _lastPlayedMs = {};

  /// Every effect is rate limited (see [_minGapMs]), so two voices cover
  /// the frequent ones and one is enough for one-off jingles. Each voice is
  /// a native player, so fewer means less memory and a faster start.
  static int voicesFor(Sfx sfx) =>
      _minGapMs.containsKey(sfx) || sfx == Sfx.freeze ? 2 : 1;

  /// Number of effect players currently alive (for tests and diagnostics).
  int get voiceCount =>
      _voices.values.fold(0, (sum, list) => sum + list.length);
  AudioPlayer? _music;
  bool _ready = false;
  bool _musicWanted = false;
  bool _suspended = false;
  GameSettings _settings = GameSettings();

  /// Minimum spacing between repeats so rapid events don't turn into noise.
  /// Every start is a platform-channel round trip, so these also bound the
  /// per-second audio cost during busy waves.
  static const Map<Sfx, int> _minGapMs = {
    Sfx.shoot: 140,
    Sfx.hit: 90,
    Sfx.pop: 70,
    Sfx.coin: 80,
    Sfx.zap: 90,
    Sfx.explode: 80,
    Sfx.armor: 80,
    Sfx.chain: 120,
  };

  /// Frequent, low-priority sounds also share one global gap.
  static const Set<Sfx> _ambient = {
    Sfx.shoot,
    Sfx.hit,
    Sfx.pop,
    Sfx.coin,
    Sfx.zap,
    Sfx.armor,
  };
  static const int _ambientGapMs = 35;
  int _lastAmbientMs = 0;

  static const Map<Sfx, double> _baseVolume = {
    Sfx.shoot: 0.18,
    Sfx.hit: 0.35,
    Sfx.pop: 0.6,
    Sfx.coin: 0.45,
    Sfx.zap: 0.35,
    Sfx.explode: 0.85,
    Sfx.chain: 0.6,
  };

  Future<void> init(GameSettings settings) async {
    _settings = settings;
    if (!enabled || _ready) return;
    final injected = _voiceLoader;
    if (injected != null) {
      await _loadVoices(injected);
      _ready = true;
      return;
    }
    try {
      // Mix with other audio so effects never steal focus from the music
      // (or from the user's own music app).
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
      await _loadVoices((sfx) => _PlayerVoice.load('audio/${sfx.name}.wav'));
      final music = AudioPlayer();
      await music.setReleaseMode(ReleaseMode.loop);
      await music.setSource(AssetSource('audio/music.wav'));
      _music = music;
      _ready = true;
      await _applyMusic();
    } catch (e) {
      debugPrint('Audio disabled: $e');
    }
  }

  /// Loads all voices in parallel (one after another took ~2 s on a phone).
  Future<void> _loadVoices(SfxVoiceLoader load) async {
    await Future.wait([
      for (final sfx in Sfx.values)
        Future.wait([for (var i = 0; i < voicesFor(sfx); i++) load(sfx)])
            .then((voices) => _voices[sfx] = voices),
    ]);
  }

  void applySettings(GameSettings settings) {
    _settings = settings;
    _applyMusic();
  }

  void play(Sfx sfx, {double volume = 1}) {
    if (!_ready || _suspended || !_settings.sfx) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = _minGapMs[sfx];
    if (gap != null && now - (_lastPlayedMs[sfx] ?? 0) < gap) return;
    final ambient = _ambient.contains(sfx);
    if (ambient && now - _lastAmbientMs < _ambientGapMs) return;
    _lastPlayedMs[sfx] = now;
    if (ambient) _lastAmbientMs = now;
    final voices = _voices[sfx];
    if (voices == null || voices.isEmpty) return;
    final i = (_nextVoice[sfx] ?? 0) % voices.length;
    _nextVoice[sfx] = i + 1;
    final v = (_baseVolume[sfx] ?? 0.8) * volume * _settings.sfxVolume;
    voices[i].play(v.clamp(0.0, 1.0)).catchError((Object _) {});
  }

  /// Requests the music loop (menus and gameplay share one track).
  void startMusic() {
    _musicWanted = true;
    _applyMusic();
  }

  void stopMusic() {
    _musicWanted = false;
    _applyMusic();
  }

  /// App went to background: silence everything.
  void suspend() {
    _suspended = true;
    _applyMusic();
  }

  void resume() {
    _suspended = false;
    _applyMusic();
  }

  Future<void> _applyMusic() async {
    final music = _music;
    if (music == null) return;
    try {
      final shouldPlay = _musicWanted && !_suspended && _settings.music;
      if (shouldPlay) {
        await music.setVolume(0.55 * _settings.musicVolume);
        if (music.state != PlayerState.playing) await music.resume();
      } else if (music.state == PlayerState.playing) {
        await music.pause();
      }
    } catch (e) {
      debugPrint('Music error: $e');
    }
  }

  Future<void> dispose() async {
    for (final voices in _voices.values) {
      for (final voice in voices) {
        await voice.dispose();
      }
    }
    _voices.clear();
    _ready = false;
    await _music?.dispose();
  }
}

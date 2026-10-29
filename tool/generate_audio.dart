// Generates every sound used by the game into assets/audio/ as 16-bit mono
// WAV files. All audio is synthesised here from scratch, so the game ships
// no third-party sound assets.
//
// Run from the project root:  dart run tool/generate_audio.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;
final _rand = math.Random(7);

void main() {
  final dir = Directory('assets/audio')..createSync(recursive: true);
  final sounds = <String, List<double>>{
    'shoot': shoot(),
    'hit': hit(),
    'pop': pop(),
    'coin': coin(),
    'upgrade': upgrade(),
    'powerup': powerUp(),
    'shield': shield(),
    'bomb': bomb(),
    'gameover': gameOver(),
    'wave': waveFanfare(),
    'click': click(),
    'explode': explode(),
    'freeze': freeze(),
    'zap': zap(),
    'armor': armorCrack(),
    'roar': roar(),
    'hurt': hurt(),
    'stageclear': stageClear(),
    'chain': chainPing(),
    'music': music(),
  };
  sounds.forEach((name, samples) {
    final file = File('${dir.path}/$name.wav');
    file.writeAsBytesSync(encodeWav(samples));
    stdout.writeln('wrote ${file.path} (${samples.length} samples)');
  });
}

// ----------------------------------------------------------------- helpers

List<double> buffer(double seconds) =>
    List<double>.filled((seconds * sampleRate).round(), 0);

double osc(String wave, double phase) {
  final p = phase - phase.floorToDouble();
  return switch (wave) {
    'sine' => math.sin(2 * math.pi * p),
    'square' => p < 0.5 ? 1.0 : -1.0,
    'triangle' => 4 * (p < 0.5 ? p : 1 - p) - 1,
    'saw' => 2 * p - 1,
    _ => 0,
  };
}

/// Adds a tone with a linear frequency sweep and an attack/decay envelope.
void tone(
  List<double> out, {
  required double start,
  required double duration,
  required double f0,
  double? f1,
  String wave = 'sine',
  double volume = 0.5,
  double attack = 0.005,
  double decayPower = 1.5,
  double vibrato = 0,
}) {
  final s0 = (start * sampleRate).round();
  final n = (duration * sampleRate).round();
  var phase = 0.0;
  for (var i = 0; i < n && s0 + i < out.length; i++) {
    final t = i / n;
    var f = f0 + ((f1 ?? f0) - f0) * t;
    if (vibrato > 0) {
      f *= 1 + vibrato * math.sin(2 * math.pi * 7 * i / sampleRate);
    }
    phase += f / sampleRate;
    final time = i / sampleRate;
    final env =
        (time < attack ? time / attack : 1.0) *
        math.pow(1 - t, decayPower).toDouble();
    out[s0 + i] += osc(wave, phase) * env * volume;
  }
}

/// Adds filtered noise (one-pole low-pass) with a decaying envelope.
void noise(
  List<double> out, {
  required double start,
  required double duration,
  double volume = 0.4,
  double cutoff = 0.2,
  double decayPower = 2,
}) {
  final s0 = (start * sampleRate).round();
  final n = (duration * sampleRate).round();
  var y = 0.0;
  for (var i = 0; i < n && s0 + i < out.length; i++) {
    final x = _rand.nextDouble() * 2 - 1;
    y += cutoff * (x - y);
    final env = math.pow(1 - i / n, decayPower).toDouble();
    out[s0 + i] += y * env * volume;
  }
}

double midi(num note) => 440 * math.pow(2, (note - 69) / 12).toDouble();

Uint8List encodeWav(List<double> samples) {
  // Normalise peaks to -1 dBFS so every file has a sane level.
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  final gain = peak > 0 ? 0.89 / peak : 1.0;
  final data = ByteData(44 + samples.length * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * gain).clamp(-1.0, 1.0);
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

// ------------------------------------------------------------------ sounds

List<double> shoot() {
  final b = buffer(0.07);
  tone(
    b,
    start: 0,
    duration: 0.06,
    f0: 1100,
    f1: 520,
    wave: 'triangle',
    volume: 0.6,
    decayPower: 2,
  );
  noise(b, start: 0, duration: 0.03, volume: 0.15, cutoff: 0.5);
  return b;
}

List<double> hit() {
  final b = buffer(0.06);
  tone(
    b,
    start: 0,
    duration: 0.05,
    f0: 420,
    f1: 260,
    wave: 'square',
    volume: 0.25,
    decayPower: 3,
  );
  noise(b, start: 0, duration: 0.04, volume: 0.35, cutoff: 0.35, decayPower: 3);
  return b;
}

List<double> pop() {
  final b = buffer(0.3);
  tone(
    b,
    start: 0,
    duration: 0.22,
    f0: 720,
    f1: 140,
    wave: 'sine',
    volume: 0.7,
    decayPower: 1.6,
  );
  tone(
    b,
    start: 0,
    duration: 0.12,
    f0: 1440,
    f1: 300,
    wave: 'triangle',
    volume: 0.2,
  );
  noise(b, start: 0, duration: 0.18, volume: 0.35, cutoff: 0.25);
  return b;
}

List<double> coin() {
  final b = buffer(0.2);
  tone(
    b,
    start: 0,
    duration: 0.07,
    f0: midi(83),
    wave: 'square',
    volume: 0.25,
    decayPower: 0.6,
  );
  tone(
    b,
    start: 0.06,
    duration: 0.13,
    f0: midi(88),
    wave: 'square',
    volume: 0.25,
    decayPower: 1.4,
  );
  return b;
}

List<double> upgrade() {
  final b = buffer(0.5);
  const notes = [72, 76, 79, 84];
  for (var i = 0; i < notes.length; i++) {
    tone(
      b,
      start: i * 0.075,
      duration: 0.2,
      f0: midi(notes[i]),
      wave: 'triangle',
      volume: 0.45,
      decayPower: 1.2,
    );
    tone(
      b,
      start: i * 0.075,
      duration: 0.2,
      f0: midi(notes[i] + 12),
      wave: 'sine',
      volume: 0.15,
    );
  }
  return b;
}

List<double> powerUp() {
  final b = buffer(0.45);
  tone(
    b,
    start: 0,
    duration: 0.4,
    f0: 300,
    f1: 1300,
    wave: 'triangle',
    volume: 0.5,
    decayPower: 0.8,
    vibrato: 0.04,
  );
  tone(
    b,
    start: 0.05,
    duration: 0.35,
    f0: 450,
    f1: 1950,
    wave: 'sine',
    volume: 0.25,
    decayPower: 1,
  );
  return b;
}

List<double> shield() {
  final b = buffer(0.5);
  tone(
    b,
    start: 0,
    duration: 0.45,
    f0: midi(64),
    wave: 'sine',
    volume: 0.5,
    decayPower: 1.2,
    vibrato: 0.01,
  );
  tone(
    b,
    start: 0,
    duration: 0.45,
    f0: midi(71),
    wave: 'sine',
    volume: 0.35,
    decayPower: 1.4,
  );
  noise(b, start: 0, duration: 0.25, volume: 0.25, cutoff: 0.08);
  return b;
}

List<double> bomb() {
  final b = buffer(0.8);
  noise(
    b,
    start: 0,
    duration: 0.75,
    volume: 0.9,
    cutoff: 0.06,
    decayPower: 2.2,
  );
  tone(
    b,
    start: 0,
    duration: 0.5,
    f0: 120,
    f1: 35,
    wave: 'sine',
    volume: 0.9,
    decayPower: 1.5,
  );
  return b;
}

List<double> gameOver() {
  final b = buffer(1.1);
  const notes = [67, 63, 60, 55];
  for (var i = 0; i < notes.length; i++) {
    tone(
      b,
      start: i * 0.18,
      duration: i == 3 ? 0.55 : 0.22,
      f0: midi(notes[i]),
      wave: 'triangle',
      volume: 0.5,
      decayPower: 1.2,
      vibrato: i == 3 ? 0.012 : 0,
    );
  }
  noise(b, start: 0, duration: 0.35, volume: 0.4, cutoff: 0.1);
  return b;
}

List<double> waveFanfare() {
  final b = buffer(0.6);
  const notes = [67, 72, 76];
  for (var i = 0; i < notes.length; i++) {
    tone(
      b,
      start: i * 0.09,
      duration: i == 2 ? 0.4 : 0.15,
      f0: midi(notes[i]),
      wave: 'square',
      volume: 0.22,
      decayPower: 1.1,
    );
    tone(
      b,
      start: i * 0.09,
      duration: i == 2 ? 0.4 : 0.15,
      f0: midi(notes[i]),
      wave: 'triangle',
      volume: 0.4,
      decayPower: 1.1,
    );
  }
  return b;
}

List<double> click() {
  final b = buffer(0.04);
  tone(
    b,
    start: 0,
    duration: 0.03,
    f0: 1600,
    f1: 900,
    wave: 'sine',
    volume: 0.6,
    decayPower: 3,
  );
  return b;
}

/// 16 second loop: Am - F - C - G at 120 BPM with bass, arpeggio and a soft
/// kick/hat pattern. Envelopes finish inside the loop so it repeats cleanly.
List<double> music() {
  const bpm = 120.0;
  const beat = 60 / bpm;
  const bars = 8;
  final b = buffer(bars * 4 * beat);
  const chords = [
    [57, 60, 64], // Am
    [53, 57, 60], // F
    [48, 52, 55], // C
    [55, 59, 62], // G
  ];
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[bar % 4];
    final barStart = bar * 4 * beat;
    // Bass: eighth notes on the root.
    for (var e = 0; e < 8; e++) {
      tone(
        b,
        start: barStart + e * beat / 2,
        duration: beat / 2 * 0.9,
        f0: midi(chord[0] - 12),
        wave: 'triangle',
        volume: 0.32,
        decayPower: 1.2,
      );
    }
    // Arpeggio: sixteenth notes up and down the chord an octave higher.
    const pattern = [0, 1, 2, 1, 0, 1, 2, 3];
    for (var s = 0; s < 16; s++) {
      final idx = pattern[s % pattern.length];
      final note = idx == 3 ? chord[0] + 12 : chord[idx];
      tone(
        b,
        start: barStart + s * beat / 4,
        duration: beat / 4 * 0.95,
        f0: midi(note + 12),
        wave: 'square',
        volume: 0.06,
        decayPower: 2,
      );
      tone(
        b,
        start: barStart + s * beat / 4,
        duration: beat / 4 * 0.95,
        f0: midi(note + 12),
        wave: 'sine',
        volume: 0.1,
        decayPower: 2,
      );
    }
    // Pad.
    for (final n in chord) {
      tone(
        b,
        start: barStart,
        duration: 4 * beat * 0.98,
        f0: midi(n),
        wave: 'sine',
        volume: 0.05,
        attack: 0.3,
        decayPower: 0.7,
      );
    }
    // Drums.
    for (var q = 0; q < 4; q++) {
      final t = barStart + q * beat;
      if (q.isEven) {
        tone(
          b,
          start: t,
          duration: 0.14,
          f0: 110,
          f1: 40,
          wave: 'sine',
          volume: 0.5,
          decayPower: 2,
        );
      } else {
        noise(b, start: t, duration: 0.12, volume: 0.12, cutoff: 0.3);
      }
      noise(
        b,
        start: t + beat / 2,
        duration: 0.03,
        volume: 0.06,
        cutoff: 0.9,
        decayPower: 3,
      );
    }
  }
  return b;
}

List<double> explode() {
  final b = buffer(0.9);
  noise(
    b,
    start: 0,
    duration: 0.85,
    volume: 1.0,
    cutoff: 0.09,
    decayPower: 2.4,
  );
  tone(
    b,
    start: 0,
    duration: 0.45,
    f0: 140,
    f1: 30,
    wave: 'sine',
    volume: 1.0,
    decayPower: 1.4,
  );
  noise(b, start: 0, duration: 0.08, volume: 0.6, cutoff: 0.7, decayPower: 3);
  return b;
}

List<double> freeze() {
  final b = buffer(0.6);
  for (var i = 0; i < 6; i++) {
    tone(
      b,
      start: i * 0.04,
      duration: 0.3,
      f0: midi(84 + i * 2),
      wave: 'sine',
      volume: 0.25,
      decayPower: 2,
    );
  }
  noise(b, start: 0, duration: 0.5, volume: 0.25, cutoff: 0.6, decayPower: 2.5);
  return b;
}

List<double> zap() {
  final b = buffer(0.22);
  final s0 = 0;
  for (var i = 0; i < b.length; i++) {
    final t = i / b.length;
    // Buzzy square with random pitch jumps for an electric crackle.
    final f = 180 + (_rand.nextDouble() * 900) * (1 - t);
    final v =
        (((i * f / sampleRate) % 1) < 0.5 ? 1 : -1) *
        math.pow(1 - t, 1.5) *
        0.35;
    b[s0 + i] += v + (_rand.nextDouble() * 2 - 1) * 0.25 * (1 - t);
  }
  return b;
}

List<double> armorCrack() {
  final b = buffer(0.35);
  noise(b, start: 0, duration: 0.3, volume: 0.8, cutoff: 0.35, decayPower: 3.5);
  tone(
    b,
    start: 0,
    duration: 0.2,
    f0: 260,
    f1: 90,
    wave: 'square',
    volume: 0.25,
    decayPower: 2,
  );
  noise(
    b,
    start: 0.05,
    duration: 0.2,
    volume: 0.4,
    cutoff: 0.12,
    decayPower: 2,
  );
  return b;
}

List<double> roar() {
  final b = buffer(1.2);
  tone(
    b,
    start: 0,
    duration: 1.1,
    f0: 95,
    f1: 60,
    wave: 'saw',
    volume: 0.5,
    attack: 0.08,
    decayPower: 1.2,
    vibrato: 0.06,
  );
  tone(
    b,
    start: 0,
    duration: 1.1,
    f0: 142,
    f1: 90,
    wave: 'square',
    volume: 0.2,
    attack: 0.08,
    decayPower: 1.3,
    vibrato: 0.05,
  );
  noise(
    b,
    start: 0,
    duration: 1.0,
    volume: 0.35,
    cutoff: 0.05,
    decayPower: 1.5,
  );
  return b;
}

List<double> hurt() {
  final b = buffer(0.4);
  tone(
    b,
    start: 0,
    duration: 0.35,
    f0: 330,
    f1: 110,
    wave: 'square',
    volume: 0.4,
    decayPower: 1.5,
  );
  noise(b, start: 0, duration: 0.25, volume: 0.5, cutoff: 0.2, decayPower: 2.5);
  return b;
}

List<double> stageClear() {
  final b = buffer(1.4);
  const notes = [72, 76, 79, 84, 79, 84, 88];
  const times = [0.0, 0.1, 0.2, 0.3, 0.5, 0.6, 0.75];
  for (var i = 0; i < notes.length; i++) {
    final last = i == notes.length - 1;
    tone(
      b,
      start: times[i],
      duration: last ? 0.6 : 0.18,
      f0: midi(notes[i]),
      wave: 'square',
      volume: 0.2,
      decayPower: 1.1,
    );
    tone(
      b,
      start: times[i],
      duration: last ? 0.6 : 0.18,
      f0: midi(notes[i]),
      wave: 'triangle',
      volume: 0.4,
      decayPower: 1.1,
      vibrato: last ? 0.01 : 0,
    );
  }
  return b;
}

List<double> chainPing() {
  final b = buffer(0.3);
  tone(
    b,
    start: 0,
    duration: 0.25,
    f0: midi(91),
    wave: 'sine',
    volume: 0.5,
    decayPower: 1.5,
  );
  tone(
    b,
    start: 0.04,
    duration: 0.22,
    f0: midi(98),
    wave: 'sine',
    volume: 0.3,
    decayPower: 1.5,
  );
  return b;
}

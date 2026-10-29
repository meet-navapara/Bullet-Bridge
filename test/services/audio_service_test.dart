import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/services/audio_service.dart';

class _FakeVoice implements SfxVoice {
  int plays = 0;
  bool disposed = false;

  @override
  Future<void> play(double volume) async => plays++;

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('effect players are reused, never created per play', () async {
    final created = <Sfx, List<_FakeVoice>>{};
    final audio = AudioService(
      voiceLoader: (sfx) async {
        final v = _FakeVoice();
        (created[sfx] ??= []).add(v);
        return v;
      },
    );
    await audio.init(GameSettings());
    final initial = audio.voiceCount;
    expect(
      initial,
      Sfx.values.map(AudioService.voicesFor).reduce((a, b) => a + b),
    );

    // A long session: far more plays than there are players.
    final watch = Stopwatch()..start();
    var calls = 0;
    while (watch.elapsedMilliseconds < 1500) {
      audio.play(Sfx.values[calls % Sfx.values.length]);
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(audio.voiceCount, initial);
    expect(created.values.expand((v) => v).length, initial);

    // Plays rotate across the fixed voices of an effect (paced past the
    // per-effect throttle).
    final pops = created[Sfx.pop]!;
    for (final v in pops) {
      v.plays = 0;
    }
    for (var i = 0; i < pops.length * 2; i++) {
      audio.play(Sfx.pop);
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    expect(pops.map((v) => v.plays), everyElement(greaterThan(0)));
    expect(audio.voiceCount, initial);

    await audio.dispose();
    expect(created.values.expand((v) => v).every((v) => v.disposed), isTrue);
    expect(audio.voiceCount, 0);
  });
}

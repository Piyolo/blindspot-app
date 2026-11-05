import 'dart:async';

import 'package:blindspot_app/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Models the Android behaviour the service has to survive: `speak`
/// stays pending until the utterance completes **or** `stop` cancels it.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.languageAvailable = true});

  final List<String> calls = <String>[];
  final StreamController<String> spoken = StreamController<String>.broadcast();
  bool languageAvailable;
  String? configuredLanguage;
  double? configuredRate;
  Completer<void>? _active;

  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {
    calls.add('configure:$language:$rate');
    configuredLanguage = language;
    configuredRate = rate;
  }

  @override
  Future<bool> isLanguageAvailable(String language) async => languageAvailable;

  @override
  Future<void> speak(String text) async {
    calls.add('speak:$text');
    spoken.add(text);
    final Completer<void> completer = Completer<void>();
    _active = completer;
    await completer.future;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final Completer<void>? active = _active;
    _active = null;
    if (active != null && !active.isCompleted) {
      active.complete();
    }
  }

  /// The utterance finishes on its own.
  void finish() {
    final Completer<void>? active = _active;
    _active = null;
    if (active != null && !active.isCompleted) {
      active.complete();
    }
  }

  Future<void> close() => spoken.close();
}

void main() {
  test('configures exactly once with the default language and rate', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine();
    final TtsService service = TtsService(engine);

    final Future<String> firstStarted = engine.spoken.stream.first;
    final Future<void> first = service.speak(
      'one',
      priority: SpeechPriority.detection,
    );
    expect(await firstStarted, 'one');
    engine.finish();
    await first;

    final Future<String> secondStarted = engine.spoken.stream.first;
    final Future<void> second = service.speak(
      'two',
      priority: SpeechPriority.detection,
    );
    expect(await secondStarted, 'two');
    engine.finish();
    await second;

    expect(
      engine.calls.where((String call) => call.startsWith('configure:')),
      <String>['configure:en-US:0.5'],
    );
    expect(engine.configuredLanguage, 'en-US');
    expect(engine.configuredRate, 0.5);
  });

  test(
    'a higher priority stops the active utterance before speaking',
    () async {
      final FakeSpeechEngine engine = FakeSpeechEngine();
      final TtsService service = TtsService(engine);

      final Future<String> detectionStarted = engine.spoken.stream.first;
      final Future<void> detection = service.speak(
        'detection',
        priority: SpeechPriority.detection,
      );
      expect(await detectionStarted, 'detection');

      final Future<String> alarmStarted = engine.spoken.stream.first;
      final Future<void> alarm = service.speak(
        'alarm',
        priority: SpeechPriority.proximityAlarm,
      );
      expect(await alarmStarted, 'alarm');
      await detection;

      expect(engine.calls, <String>[
        'configure:en-US:0.5',
        'speak:detection',
        'stop',
        'speak:alarm',
      ]);

      engine.finish();
      await alarm;
    },
  );

  test('an equal priority stops the active utterance too', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine();
    final TtsService service = TtsService(engine);

    final Future<String> firstStarted = engine.spoken.stream.first;
    final Future<void> first = service.speak(
      'first',
      priority: SpeechPriority.detection,
    );
    expect(await firstStarted, 'first');

    final Future<String> secondStarted = engine.spoken.stream.first;
    final Future<void> second = service.speak(
      'second',
      priority: SpeechPriority.detection,
    );
    expect(await secondStarted, 'second');
    await first;

    expect(engine.calls, <String>[
      'configure:en-US:0.5',
      'speak:first',
      'stop',
      'speak:second',
    ]);

    engine.finish();
    await second;
  });

  test('a lower priority is dropped while speaking', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine();
    final TtsService service = TtsService(engine);

    final Future<String> alarmStarted = engine.spoken.stream.first;
    final Future<void> alarm = service.speak(
      'alarm',
      priority: SpeechPriority.proximityAlarm,
    );
    expect(await alarmStarted, 'alarm');

    await service.speak('detection', priority: SpeechPriority.detection);
    expect(engine.calls, isNot(contains('speak:detection')));

    engine.finish();
    await alarm;
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, isNot(contains('speak:detection')));
  });

  test(
    'keeps one command response and speaks it after the active one',
    () async {
      final FakeSpeechEngine engine = FakeSpeechEngine();
      final TtsService service = TtsService(engine);

      final Future<String> alarmStarted = engine.spoken.stream.first;
      final Future<void> alarm = service.speak(
        'alarm',
        priority: SpeechPriority.proximityAlarm,
      );
      expect(await alarmStarted, 'alarm');

      await service.speak('answer', priority: SpeechPriority.commandResponse);
      expect(engine.calls, isNot(contains('speak:answer')));

      final Future<String> answerStarted = engine.spoken.stream.first;
      engine.finish();
      expect(await answerStarted, 'answer');
      await alarm;
      expect(engine.calls, <String>[
        'configure:en-US:0.5',
        'speak:alarm',
        'speak:answer',
      ]);

      engine.finish();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('stop all clears the pending command and stops the engine', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine();
    final TtsService service = TtsService(engine);

    final Future<String> alarmStarted = engine.spoken.stream.first;
    final Future<void> alarm = service.speak(
      'alarm',
      priority: SpeechPriority.proximityAlarm,
    );
    expect(await alarmStarted, 'alarm');
    await service.speak('answer', priority: SpeechPriority.commandResponse);

    await service.stopAll();
    await alarm;
    engine.finish();
    await Future<void>.delayed(Duration.zero);

    expect(engine.calls, contains('stop'));
    expect(engine.calls, isNot(contains('speak:answer')));
  });

  test(
    'dispose during speech completes without throwing and is idempotent',
    () async {
      final FakeSpeechEngine engine = FakeSpeechEngine();
      final TtsService service = TtsService(engine);

      final Future<String> started = engine.spoken.stream.first;
      final Future<void> speaking = service.speak(
        'speaking',
        priority: SpeechPriority.detection,
      );
      expect(await started, 'speaking');

      await service.dispose();
      await speaking;
      await service.dispose();

      expect(engine.calls.where((String call) => call == 'stop'), hasLength(1));
      // Speech after disposal is ignored, not an error.
      await service.speak('ignored', priority: SpeechPriority.proximityAlarm);
      expect(engine.calls, isNot(contains('speak:ignored')));
    },
  );

  test('falls back to English when fil-PH is unavailable', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine(languageAvailable: false);
    final TtsService service = TtsService(engine, language: 'fil-PH');

    final Future<String> started = engine.spoken.stream.first;
    final Future<void> speaking = service.speak(
      'hello',
      priority: SpeechPriority.detection,
    );
    expect(await started, 'hello');

    expect(engine.configuredLanguage, 'en-US');
    engine.finish();
    await speaking;
  });

  test('uses fil-PH when the engine reports it available', () async {
    final FakeSpeechEngine engine = FakeSpeechEngine(languageAvailable: true);
    final TtsService service = TtsService(engine, language: 'fil-PH');

    final Future<String> started = engine.spoken.stream.first;
    final Future<void> speaking = service.speak(
      'kumusta',
      priority: SpeechPriority.detection,
    );
    expect(await started, 'kumusta');

    expect(engine.configuredLanguage, 'fil-PH');
    engine.finish();
    await speaking;
  });
}

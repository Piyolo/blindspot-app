import 'package:flutter_tts/flutter_tts.dart';

import 'tts_service.dart';

/// Production [SpeechEngine] backed by `flutter_tts`.
///
/// Only this file touches the plugin, so `TtsService` and its tests stay
/// platform-free. `awaitSpeakCompletion(true)` is what makes [speak] mean
/// "until the utterance ends"; it only takes effect together with the
/// flush queue mode, so both are set in [configure].
class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// `TextToSpeech.QUEUE_FLUSH`.
  static const int _queueFlush = 0;

  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setQueueMode(_queueFlush);
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<bool> isLanguageAvailable(String language) async =>
      await _tts.isLanguageAvailable(language) == true;

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

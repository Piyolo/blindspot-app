import 'dart:async';

/// Who is speaking, lowest first. The values are the donor's priorities
/// (spec §6.3): a detection must never talk over an alarm, and the SOS
/// countdown must never be talked over by anything.
enum SpeechPriority {
  detection(3),
  commandResponse(7),
  proximityAlarm(9),
  sosCountdown(10);

  const SpeechPriority(this.value);

  /// Larger wins.
  final int value;
}

/// Thin seam over the platform TTS engine.
///
/// The production implementation is `FlutterTtsEngine`; tests use a fake
/// that models Android's behaviour, including the fact that [speak] only
/// completes when the utterance ends (or [stop] cancels it).
abstract class SpeechEngine {
  /// Configures the engine once: await-completion on, flush queue, language
  /// and rate.
  Future<void> configure({required String language, required double rate});

  /// Whether the device can speak [language].
  Future<bool> isLanguageAvailable(String language);

  /// Speaks [text]; the future completes when the utterance finishes.
  Future<void> speak(String text);

  /// Cancels the active utterance, completing its [speak] future.
  Future<void> stop();
}

/// Priority speech queue for detection announcements, alarms and answers.
///
/// Rules (spec §6.3):
/// - a request with a priority **higher or equal** to the active utterance
///   stops it and speaks immediately (newest detection wins);
/// - a lower-priority request is **dropped** while something is speaking,
///   except one `commandResponse`, which is kept and spoken when the active
///   utterance ends;
/// - every engine command is serialised, because Android's flush-mode
///   `speak` silently returns `0` when another utterance is active;
/// - the engine is configured lazily, exactly once, falling back to
///   `en-US` when the requested language is unavailable.
///
/// Engine failures are treated as a finished utterance and never thrown at
/// the caller: a broken TTS engine must not stop detection or the alarm.
/// The future returned by [speak] completes when the utterance ends or is
/// superseded; a dropped or queued request completes immediately.
class TtsService {
  TtsService(this._engine, {String language = 'en-US', double rate = 0.5})
    : _language = language,
      _rate = rate;

  final SpeechEngine _engine;
  final String _language;
  final double _rate;

  /// Serialises engine commands (configure, stop, speak-start). The active
  /// utterance is deliberately *not* awaited inside the queue: a
  /// preemption must be able to issue `stop` while `speak` is pending.
  final _CommandQueue _queue = _CommandQueue();

  bool _disposed = false;
  bool _configured = false;
  Future<void>? _configuring;

  /// The utterance that currently owns the engine, if any.
  _ActiveSpeech? _active;

  /// At most one command response waiting for the active utterance.
  _PendingSpeech? _pendingCommand;

  /// Speaks [text] at [priority].
  Future<void> speak(String text, {required SpeechPriority priority}) async {
    if (_disposed) {
      return;
    }
    await _ensureConfigured();
    if (_disposed) {
      return;
    }

    final _ActiveSpeech? active = _active;
    if (active != null && priority.value < active.priority.value) {
      if (priority == SpeechPriority.commandResponse) {
        // One answer is kept, and the newest answer replaces it: the user
        // asked again, so the stale answer is no longer useful.
        _pendingCommand = _PendingSpeech(text);
      }
      return;
    }

    await _start(text, priority);
  }

  /// Clears anything waiting and stops the engine immediately.
  Future<void> stopAll() async {
    if (_disposed) {
      return;
    }
    _clearPendingAndActive();
    await _stopEngine();
  }

  /// Stops speech and ignores every later request. Idempotent.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _clearPendingAndActive();
    await _stopEngine();
  }

  Future<void> _ensureConfigured() {
    if (_configured) {
      return Future<void>.value();
    }
    final Future<void>? inFlight = _configuring;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<void> future = _configureOnce().whenComplete(() {
      _configuring = null;
    });
    _configuring = future;
    return future;
  }

  Future<void> _configureOnce() async {
    String language = _language;
    if (language != 'en-US') {
      bool available = false;
      try {
        available = await _engine.isLanguageAvailable(language);
      } catch (_) {
        available = false;
      }
      if (!available) {
        language = 'en-US';
      }
    }
    try {
      await _engine.configure(language: language, rate: _rate);
      _configured = true;
    } catch (_) {
      // Best effort: retried by the next speak, and a failure must not
      // stop detection. A partially configured engine still speaks.
    }
  }

  /// Makes [text] the active utterance, preempting [previous].
  ///
  /// Returns a future that completes when this utterance stops being the
  /// active one — normally at its end, or as soon as a newer request
  /// supersedes it.
  Future<void> _start(String text, SpeechPriority priority) {
    final _ActiveSpeech? previous = _active;
    final _ActiveSpeech speech = _ActiveSpeech(priority);
    _active = speech;
    // The previous caller should not wait for Android's stop to land.
    previous?.complete();

    unawaited(
      _queue.run<void>(() async {
        try {
          // A newer request may have won before this one reached the
          // engine; never start a superseded utterance.
          if (_disposed || !identical(_active, speech)) {
            return;
          }
          if (previous != null) {
            await _engine.stop();
          }
          if (_disposed || !identical(_active, speech)) {
            return;
          }
          final Future<void> utterance = _engine.speak(text);
          unawaited(
            utterance.then(
              (_) => _onUtteranceDone(speech),
              onError: (Object _, StackTrace _) => _onUtteranceDone(speech),
            ),
          );
        } catch (_) {
          // A failed utterance is treated as finished so the queue cannot
          // wedge and the next announcement still speaks.
          _onUtteranceDone(speech);
        }
      }),
    );
    return speech.done;
  }

  void _onUtteranceDone(_ActiveSpeech speech) {
    speech.complete();
    if (_disposed || !identical(_active, speech)) {
      return;
    }
    _active = null;
    final _PendingSpeech? pending = _pendingCommand;
    if (pending == null) {
      return;
    }
    _pendingCommand = null;
    unawaited(_start(pending.text, SpeechPriority.commandResponse));
  }

  void _clearPendingAndActive() {
    _pendingCommand = null;
    final _ActiveSpeech? active = _active;
    _active = null;
    active?.complete();
  }

  Future<void> _stopEngine() {
    return _queue.run<void>(() async {
      try {
        await _engine.stop();
      } catch (_) {
        // A failed stop must not wedge the queue.
      }
    });
  }
}

/// One utterance that owns the engine until it ends or is superseded.
class _ActiveSpeech {
  _ActiveSpeech(this.priority);

  final SpeechPriority priority;
  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  void complete() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

/// A command response waiting for the active utterance to end.
class _PendingSpeech {
  const _PendingSpeech(this.text);

  final String text;
}

/// Runs engine commands one at a time, in call order. A failing action
/// completes its own future with the error and leaves the queue usable.
class _CommandQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

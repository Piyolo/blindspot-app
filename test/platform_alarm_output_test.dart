import 'package:blindspot_app/services/detection/platform_alarm_output.dart';
import 'package:blindspot_app/services/detection/proximity_alarm.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeechEngine implements SpeechEngine {
  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String channelName = 'blindspot/system';
  const StandardMethodCodec codec = StandardMethodCodec();

  late List<MethodCall> calls;
  late ByteData? Function(MethodCall call) respond;

  setUp(() {
    calls = <MethodCall>[];
    respond = (MethodCall call) => codec.encodeSuccessEnvelope(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channelName, (ByteData? message) async {
          final MethodCall call = codec.decodeMethodCall(message);
          calls.add(call);
          return respond(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channelName, null);
  });

  test('vibrate sends the millisecond argument', () async {
    await PlatformAlarmOutput().vibrate(300);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'vibrate');
    expect(calls.single.arguments, <String, Object?>{'ms': 300});
  });

  test('playAlarm and stopAlarm send no arguments', () async {
    final PlatformAlarmOutput output = PlatformAlarmOutput();
    await output.playAlarm();
    await output.stopAlarm();
    expect(calls.map((MethodCall call) => call.method), <String>[
      'playAlarm',
      'stopAlarm',
    ]);
    expect(calls.every((MethodCall call) => call.arguments == null), isTrue);
  });

  test(
    'a PlatformException is swallowed, never thrown at the caller',
    () async {
      respond = (MethodCall call) =>
          codec.encodeErrorEnvelope(code: 'boom', message: 'no vibrator');
      await expectLater(PlatformAlarmOutput().vibrate(300), completes);
      expect(calls.single.method, 'vibrate');
    },
  );

  test('disposing the alarm calls stopAlarm over the channel', () async {
    final ProximityAlarm alarm = ProximityAlarm(
      output: PlatformAlarmOutput(),
      tts: TtsService(FakeSpeechEngine()),
    );
    await alarm.dispose();
    expect(calls.map((MethodCall call) => call.method), contains('stopAlarm'));
  });
}

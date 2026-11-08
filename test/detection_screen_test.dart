import 'dart:async';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/screens/detection_screen.dart';
import 'package:blindspot_app/services/detection/detection_engine.dart';
import 'package:blindspot_app/theme/app_theme.dart';
import 'package:blindspot_app/widgets/bbox_overlay.dart';
import 'package:blindspot_app/widgets/object_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWakelock implements ScreenWakelock {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async {
    enableCalls++;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
  }
}

/// Records every announcement message sent over the accessibility channel,
/// mirroring the other screen suites.
List<String> recordAnnouncements(WidgetTester tester) {
  final List<String> messages = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    SystemChannels.accessibility.name,
    (ByteData? message) async {
      final Object? json = const StandardMessageCodec().decodeMessage(message);
      if (json is Map<Object?, Object?> && json['type'] == 'announce') {
        final Object? data = json['data'];
        if (data is Map<Object?, Object?> && data['message'] is String) {
          messages.add(data['message']! as String);
        }
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    ),
  );
  return messages;
}

Detection detection({
  required String label,
  required Rect box,
  double? distance,
  double confidence = 0.9,
}) {
  return Detection(
    label: label,
    confidence: confidence,
    box: box,
    distanceMeters: distance,
    direction: DetectionDirection.ahead,
  );
}

const Rect aheadBox = Rect.fromLTRB(300, 0, 340, 40);

Future<FakeWakelock> pumpDetection(
  WidgetTester tester, {
  DetectionEngineStatus status = DetectionEngineStatus.running,
  List<Detection> detections = const <Detection>[],
  Size? frameSize = const Size(640, 480),
  bool hasTorch = false,
  bool torchOn = false,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  Future<void> Function()? onStop,
  Future<void> Function()? onRetry,
  Future<void> Function()? onToggleTorch,
  FakeWakelock? wakelock,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeWakelock lock = wakelock ?? FakeWakelock();
  final Widget app = MaterialApp(
    theme: AppTheme.dark(),
    routes: <String, WidgetBuilder>{
      '/': (_) => const Scaffold(body: Center(child: Text('stub-home'))),
      '/detection': (_) => DetectionScreen(
        status: status,
        detections: detections,
        frameSize: frameSize,
        hasTorch: hasTorch,
        torchOn: torchOn,
        onStop: onStop ?? () async {},
        onRetry: onRetry ?? () async {},
        onToggleTorch: onToggleTorch ?? () async {},
        previewBuilder: (_) => const ColoredBox(
          key: ValueKey<String>('fakePreview'),
          color: Colors.blue,
        ),
        wakelock: lock,
      ),
    },
    initialRoute: '/',
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(
        tester.view,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app,
    ),
  );
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/detection');
  await tester.pumpAndSettle();
  return lock;
}

void main() {
  group('states', () {
    testWidgets('starting shows the starting copy and no overlay', (
      WidgetTester tester,
    ) async {
      await pumpDetection(tester, status: DetectionEngineStatus.starting);

      expect(find.text(Copy.detectionStarting), findsOneWidget);
      expect(find.byType(BboxOverlay), findsNothing);
      expect(find.byType(ObjectRow), findsNothing);
      expect(find.text(Copy.stopDetection), findsOneWidget);
    });

    testWidgets('a camera error shows the error copy and retries once', (
      WidgetTester tester,
    ) async {
      int retryCalls = 0;
      await pumpDetection(
        tester,
        status: DetectionEngineStatus.error,
        onRetry: () async {
          retryCalls++;
        },
      );

      expect(find.text(Copy.cameraError), findsOneWidget);
      expect(find.text(Copy.retry), findsOneWidget);
      await tester.tap(find.text(Copy.retry));
      await tester.pump();
      expect(retryCalls, 1);
      expect(find.text(Copy.cameraError), findsOneWidget);
      expect(find.text(Copy.stopDetection), findsOneWidget);
    });

    testWidgets('an empty running frame shows the no-objects copy', (
      WidgetTester tester,
    ) async {
      await pumpDetection(tester);

      expect(find.text(Copy.noObjects), findsOneWidget);
      expect(find.text(Copy.watching), findsNothing);
      expect(find.byType(ObjectRow), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('detectionScrim')),
        findsOneWidget,
      );
    });

    testWidgets('detections show watching, the heading and the rows', (
      WidgetTester tester,
    ) async {
      await pumpDetection(
        tester,
        detections: <Detection>[
          detection(label: 'Chair', box: aheadBox, distance: 1.2),
        ],
      );

      expect(find.text(Copy.watching), findsOneWidget);
      expect(find.text(Copy.objectsHeading), findsOneWidget);
      expect(find.byType(ObjectRow), findsOneWidget);
      expect(find.text('Chair'), findsOneWidget);
      expect(find.byType(BboxOverlay), findsOneWidget);
      final ColoredBox scrim = tester.widget<ColoredBox>(
        find.byKey(const ValueKey<String>('detectionScrim')),
      );
      expect(scrim.color, const Color(0x66000000));
    });

    testWidgets('object rows are ordered nearest first, unknowns last', (
      WidgetTester tester,
    ) async {
      await pumpDetection(
        tester,
        detections: <Detection>[
          detection(label: 'Chair', box: aheadBox, distance: 2.0),
          detection(label: 'Sofa', box: aheadBox, distance: 0.8),
          detection(label: 'Bed', box: aheadBox),
          detection(label: 'Table', box: aheadBox, distance: 1.5),
        ],
      );

      final List<String> labels = tester
          .widgetList<ObjectRow>(find.byType(ObjectRow))
          .map((ObjectRow row) => row.detection.label)
          .toList(growable: false);
      expect(labels, <String>['Sofa', 'Table', 'Chair', 'Bed']);
    });
  });

  group('controls', () {
    testWidgets('stop awaits the provider, pops and announces', (
      WidgetTester tester,
    ) async {
      final List<String> announcements = recordAnnouncements(tester);
      final Completer<void> stopCompleter = Completer<void>();
      int stopCalls = 0;
      final FakeWakelock lock = await pumpDetection(
        tester,
        onStop: () {
          stopCalls++;
          return stopCompleter.future;
        },
      );

      await tester.tap(find.text(Copy.stopDetection));
      await tester.pump();
      // The button is disabled while stopping; a second tap is inert.
      await tester.tap(find.text(Copy.stopDetection));
      await tester.pump();
      expect(stopCalls, 1);
      expect(find.byType(DetectionScreen), findsOneWidget);
      expect(announcements, isEmpty);

      stopCompleter.complete();
      await tester.pumpAndSettle();
      expect(find.text('stub-home'), findsOneWidget);
      expect(find.byType(DetectionScreen), findsNothing);
      expect(announcements, <String>[Copy.detectionStopped]);
      expect(lock.enableCalls, 1);
      expect(lock.disableCalls, 1);
    });

    testWidgets('the flash toggle shows the action and calls the provider', (
      WidgetTester tester,
    ) async {
      int torchCalls = 0;
      await pumpDetection(
        tester,
        hasTorch: true,
        onToggleTorch: () async {
          torchCalls++;
        },
      );

      expect(find.text(Copy.flashOn), findsOneWidget);
      expect(find.text(Copy.flashOff), findsNothing);
      await tester.tap(find.text(Copy.flashOn));
      await tester.pump();
      expect(torchCalls, 1);
    });

    testWidgets('the flash toggle reflects an active torch', (
      WidgetTester tester,
    ) async {
      await pumpDetection(tester, hasTorch: true, torchOn: true);

      expect(find.text(Copy.flashOff), findsOneWidget);
      expect(find.text(Copy.flashOn), findsNothing);
    });

    testWidgets('a camera without a torch has no flash toggle', (
      WidgetTester tester,
    ) async {
      await pumpDetection(tester, hasTorch: false);

      expect(find.text(Copy.flashOn), findsNothing);
      expect(find.text(Copy.flashOff), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('the status is a live region and the stop button is labelled', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpDetection(
        tester,
        detections: <Detection>[
          detection(label: 'Chair', box: aheadBox, distance: 1.2),
        ],
      );

      final Iterable<Semantics> live = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (Semantics semantics) => semantics.properties.liveRegion == true,
          );
      expect(live, isNotEmpty);
      expect(find.bySemanticsLabel(Copy.stopDetection), findsOneWidget);
      expect(
        find.bySemanticsLabel('Chair, approximately 1 meter, ahead'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('every status-bar region is the shared dark style', (
      WidgetTester tester,
    ) async {
      await pumpDetection(tester);

      final List<AnnotatedRegion<SystemUiOverlayStyle>> regions = tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .toList(growable: false);
      expect(regions, isNotEmpty);
      for (final AnnotatedRegion<SystemUiOverlayStyle> region in regions) {
        expect(region.value, AppTheme.statusBarStyle);
      }
    });
  });

  group('text scale', () {
    testWidgets('1.0x-3.0x on a 320x568 screen never overflows', (
      WidgetTester tester,
    ) async {
      final List<Detection> detections = <Detection>[
        detection(label: 'Chair', box: aheadBox, distance: 0.9),
        detection(label: 'Table', box: aheadBox, distance: 1.5),
        detection(label: 'Electric Fan', box: aheadBox, distance: 2.3),
        detection(label: 'Refrigerator', box: aheadBox),
      ];
      final List<double> previewHeights = <double>[];

      for (final double scale in <double>[1.0, 2.0, 3.0]) {
        await pumpDetection(
          tester,
          detections: detections,
          textScale: scale,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull, reason: 'text scale $scale');
        expect(find.text(Copy.stopDetection), findsOneWidget);
        previewHeights.add(
          tester
              .getSize(find.byKey(const ValueKey<String>('detectionPreview')))
              .height,
        );
      }

      expect(previewHeights.last, lessThan(previewHeights.first));
    });
  });
}

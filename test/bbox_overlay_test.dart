import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/widgets/bbox_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Detection detection(String label, Rect box) {
  return Detection(
    label: label,
    confidence: 0.9,
    box: box,
    distanceMeters: 1.0,
    direction: DetectionDirection.ahead,
  );
}

void main() {
  group('BboxPainter', () {
    test('produces one path per mapped detection', () {
      final BboxPainter painter = BboxPainter(
        detections: <Detection>[
          detection('Chair', const Rect.fromLTRB(320, 320, 340, 340)),
          detection('Table', const Rect.fromLTRB(100, 100, 200, 200)),
        ],
        frameSize: const Size(640, 480),
        viewSize: const Size(320, 240),
      );

      expect(painter.paths, hasLength(2));
      expect(
        painter.paths.first.getBounds(),
        rectMoreOrLessEquals(const Rect.fromLTRB(160, 120, 170, 130)),
      );
      expect(
        painter.paths.last.getBounds(),
        rectMoreOrLessEquals(const Rect.fromLTRB(50, 10, 100, 60)),
      );
    });

    test('skips degenerate boxes', () {
      final BboxPainter painter = BboxPainter(
        detections: <Detection>[
          detection('Chair', const Rect.fromLTRB(320, 320, 340, 340)),
          detection('Flat', const Rect.fromLTRB(100, 100, 100, 140)),
          detection('Inverted', const Rect.fromLTRB(200, 200, 150, 240)),
        ],
        frameSize: const Size(640, 480),
        viewSize: const Size(320, 240),
      );

      expect(painter.paths, hasLength(1));
    });

    test('an empty detection list paints nothing', () {
      final BboxPainter painter = BboxPainter(
        detections: const <Detection>[],
        frameSize: const Size(640, 480),
        viewSize: const Size(320, 240),
      );

      expect(painter.paths, isEmpty);
    });

    test('repaints when the detections or either size changes', () {
      const List<Detection> detections = <Detection>[];
      final BboxPainter base = BboxPainter(
        detections: detections,
        frameSize: const Size(640, 480),
        viewSize: const Size(320, 240),
      );

      expect(
        base.shouldRepaint(
          BboxPainter(
            detections: const <Detection>[],
            frameSize: const Size(640, 480),
            viewSize: const Size(320, 240),
          ),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          BboxPainter(
            detections: const <Detection>[],
            frameSize: const Size(480, 640),
            viewSize: const Size(320, 240),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          BboxPainter(
            detections: const <Detection>[],
            frameSize: const Size(640, 480),
            viewSize: const Size(240, 320),
          ),
        ),
        isTrue,
      );
    });
  });

  group('BboxOverlay', () {
    testWidgets('renders a non-interactive CustomPaint with the painter', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: BboxOverlay(
                detections: <Detection>[
                  detection('Chair', const Rect.fromLTRB(320, 320, 340, 340)),
                ],
                frameSize: const Size(640, 480),
                viewSize: const Size(320, 240),
              ),
            ),
          ),
        ),
      );

      final Finder paint = find.descendant(
        of: find.byType(BboxOverlay),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsOneWidget);
      expect(tester.getSize(paint), const Size(320, 240));
      expect(tester.widget<CustomPaint>(paint).painter, isA<BboxPainter>());
      expect(
        find.descendant(
          of: find.byType(BboxOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });
}

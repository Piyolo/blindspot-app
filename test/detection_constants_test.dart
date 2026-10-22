import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/constants/detection.dart';
import 'package:blindspot_app/models/detection.dart';

/// Phase-2 detection thresholds, pinned verbatim from the plan
/// (`docs/superpowers/plans/2026-10-21-blindspot-phase2-detection.md`,
/// Task 1). Per `p2-global-constraints.md` no code may re-derive these
/// numbers, and a test must fail if any of them moves.
void main() {
  /// The `labelsV5.txt` class order, spelled exactly as the asset writes
  /// it: lower-case, `electric fan` with a space. This pins the
  /// `DetectionConstants.realWidthCm` key set (the labelsV5 pin).
  const List<String> labelsV5 = <String>[
    'bed',
    'cabinet',
    'chair',
    'door',
    'electric fan',
    'laptop',
    'monitor',
    'person',
    'refrigerator',
    'sink',
    'sofa',
    'table',
    'television',
    'toilet',
  ];

  group('DetectionConstants', () {
    test(
      'realWidthCm holds exactly the 14 labelsV5 labels with plan widths',
      () {
        expect(DetectionConstants.realWidthCm, <String, int>{
          'bed': 100,
          'cabinet': 80,
          'chair': 45,
          'door': 80,
          'electric fan': 40,
          'laptop': 35,
          'monitor': 60,
          'person': 40,
          'refrigerator': 70,
          'sink': 50,
          'sofa': 150,
          'table': 120,
          'television': 100,
          'toilet': 38,
        });
        expect(DetectionConstants.realWidthCm.keys, unorderedEquals(labelsV5));
      },
    );

    test('labelAliases maps tv and wc to their class names', () {
      expect(DetectionConstants.labelAliases, <String, String>{
        'tv': 'television',
        'wc': 'toilet',
      });
    });

    test('every real width is positive', () {
      DetectionConstants.realWidthCm.forEach((String label, int widthCm) {
        expect(widthCm, greaterThan(0), reason: 'real width of $label');
      });
    });

    test('confidenceBalanced and nmsIou sit strictly between 0 and 1', () {
      expect(DetectionConstants.confidenceBalanced, greaterThan(0));
      expect(DetectionConstants.confidenceBalanced, lessThan(1));
      expect(DetectionConstants.nmsIou, greaterThan(0));
      expect(DetectionConstants.nmsIou, lessThan(1));
    });

    test('thermal backoff tiers ascend past the frame minimum interval', () {
      expect(DetectionConstants.thermalBackoffMs, isNotEmpty);
      for (int i = 0; i < DetectionConstants.thermalBackoffMs.length; i++) {
        expect(
          DetectionConstants.thermalBackoffMs[i],
          greaterThan(DetectionConstants.frameMinIntervalMs),
          reason: 'tier $i must exceed the frame minimum interval',
        );
        if (i > 0) {
          expect(
            DetectionConstants.thermalBackoffMs[i],
            greaterThan(DetectionConstants.thermalBackoffMs[i - 1]),
            reason: 'tier $i must exceed tier ${i - 1}',
          );
        }
      }
    });

    test('proximityMeters is strictly below one metre', () {
      expect(DetectionConstants.proximityMeters, lessThan(1));
    });

    test('a same-label announcement waits longer than a label change', () {
      expect(
        DetectionConstants.announceSameLabelMinMs,
        greaterThan(DetectionConstants.announceChangedLabelMs),
      );
      expect(
        DetectionConstants.announceSameLabelMaxMs,
        greaterThan(DetectionConstants.announceSameLabelMinMs),
      );
    });

    test('every plan threshold is pinned verbatim', () {
      expect(DetectionConstants.inputSize, 640);
      expect(DetectionConstants.padValue, 114);
      expect(DetectionConstants.confidenceBalanced, 0.60);
      expect(DetectionConstants.nmsIou, 0.50);
      expect(DetectionConstants.frameMinIntervalMs, 600);
      expect(DetectionConstants.thermalBackoffMs, <int>[1200, 2000]);
      expect(DetectionConstants.thermalSlowMs, 350);
      expect(DetectionConstants.thermalRecoverMs, 10000);
      expect(DetectionConstants.motionSize, 112);
      expect(DetectionConstants.motionMad, 18);
      expect(DetectionConstants.focalLengthPx, 980);
      expect(DetectionConstants.proximityMeters, 0.7);
      expect(DetectionConstants.proximityVibrateMs, 300);
      expect(DetectionConstants.proximityCooldownMs, 3000);
      expect(DetectionConstants.announceChangedLabelMs, 2000);
      expect(DetectionConstants.announceSameLabelMinMs, 4000);
      expect(DetectionConstants.announceSameLabelMaxMs, 5000);
    });
  });

  group('directionFor', () {
    test('splits the default 640-wide frame into thirds', () {
      expect(
        directionFor(const Rect.fromLTRB(80, 0, 120, 40)),
        DetectionDirection.left,
      );
      expect(
        directionFor(const Rect.fromLTRB(300, 0, 340, 40)),
        DetectionDirection.ahead,
      );
      expect(
        directionFor(const Rect.fromLTRB(580, 0, 620, 40)),
        DetectionDirection.right,
      );
    });

    test('exactly width/3 is ahead — the left boundary is strict', () {
      // Zero-width marker boxes: their centre is exactly the boundary
      // value with no floating-point drift.
      expect(
        directionFor(Rect.fromLTRB(640 / 3, 0, 640 / 3, 40)),
        DetectionDirection.ahead,
      );
      // A regular box just below the boundary flips to left.
      expect(
        directionFor(Rect.fromLTRB(640 / 3 - 1, 0, 640 / 3 - 1, 40)),
        DetectionDirection.left,
      );
      // Non-degenerate box on the boundary with a custom width: centre 200
      // is exactly 600/3 (under the default 640 it would read as left).
      expect(
        directionFor(const Rect.fromLTRB(190, 0, 210, 40), width: 600),
        DetectionDirection.ahead,
      );
      expect(
        directionFor(const Rect.fromLTRB(180, 0, 218, 40), width: 600),
        DetectionDirection.left,
      );
    });

    test('exactly 2*width/3 is ahead — the right boundary is strict', () {
      expect(
        directionFor(Rect.fromLTRB(2 * 640 / 3, 0, 2 * 640 / 3, 40)),
        DetectionDirection.ahead,
      );
      // Just past the boundary flips to right; just short of it stays ahead.
      expect(
        directionFor(Rect.fromLTRB(2 * 640 / 3 + 1, 0, 2 * 640 / 3 + 1, 40)),
        DetectionDirection.right,
      );
      expect(
        directionFor(Rect.fromLTRB(2 * 640 / 3 - 1, 0, 2 * 640 / 3 - 1, 40)),
        DetectionDirection.ahead,
      );
      // Non-degenerate box on the boundary: centre 400 is exactly 2*600/3.
      expect(
        directionFor(const Rect.fromLTRB(390, 0, 410, 40), width: 600),
        DetectionDirection.ahead,
      );
      expect(
        directionFor(const Rect.fromLTRB(392, 0, 412, 40), width: 600),
        DetectionDirection.right,
      );
    });
  });

  group('Detection', () {
    test('is const-constructible with every field readable back', () {
      const Detection detection = Detection(
        label: 'chair',
        confidence: 0.75,
        box: Rect.fromLTRB(10, 20, 110, 220),
        distanceMeters: 1.5,
        direction: DetectionDirection.ahead,
      );
      expect(detection.label, 'chair');
      expect(detection.confidence, 0.75);
      expect(detection.box, const Rect.fromLTRB(10, 20, 110, 220));
      expect(detection.distanceMeters, 1.5);
      expect(detection.direction, DetectionDirection.ahead);
    });

    test('distanceMeters stays null for an unknown label', () {
      const Detection detection = Detection(
        label: 'object',
        confidence: 0.9,
        box: Rect.fromLTRB(0, 0, 64, 64),
        distanceMeters: null,
        direction: DetectionDirection.left,
      );
      expect(detection.distanceMeters, isNull);
    });
  });
}

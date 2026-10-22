import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/services/detection/depth_estimator.dart';

/// Task 3 (`2026-10-21-blindspot-phase2-detection.md`): the width-based
/// depth estimate and its distance bucketing. Every expected value below
/// is hand-computed from the plan formula
/// `cm = realWidthCm * 980 / boxWidthPx`, `m = cm / 100`, bucketed
/// *before* rounding (`m < 1.0` → nearest 10 cm with a 10 cm floor and a
/// 100 cm → 1 m promotion; `m >= 1.0` → whole metres).
void main() {
  group('estimateDistanceMeters', () {
    /// One row per `labelsV5` class: the pixel width is chosen so the
    /// division lands on an exact integer centimetre value.
    /// `(label, boxWidthPx, hand computation, expected phrase)`.
    final List<(String, double, String, DistancePhrase)>
    cases = <(String, double, String, DistancePhrase)>[
      ('bed', 490, '100 * 980 / 490 = 200 cm = 2.0 m', MetersPhrase(2)),
      ('cabinet', 392, '80 * 980 / 392 = 200 cm = 2.0 m', MetersPhrase(2)),
      ('chair', 882, '45 * 980 / 882 = 50 cm = 0.5 m', CentimetersPhrase(50)),
      ('door', 980, '80 * 980 / 980 = 80 cm = 0.8 m', CentimetersPhrase(80)),
      (
        'electric fan',
        980,
        '40 * 980 / 980 = 40 cm = 0.4 m',
        CentimetersPhrase(40),
      ),
      ('laptop', 490, '35 * 980 / 490 = 70 cm = 0.7 m', CentimetersPhrase(70)),
      ('monitor', 588, '60 * 980 / 588 = 100 cm = 1.0 m', MetersPhrase(1)),
      ('person', 196, '40 * 980 / 196 = 200 cm = 2.0 m', MetersPhrase(2)),
      (
        'refrigerator',
        490,
        '70 * 980 / 490 = 140 cm = 1.4 m → rounds to 1 m',
        MetersPhrase(1),
      ),
      ('sink', 490, '50 * 980 / 490 = 100 cm = 1.0 m', MetersPhrase(1)),
      ('sofa', 490, '150 * 980 / 490 = 300 cm = 3.0 m', MetersPhrase(3)),
      ('table', 588, '120 * 980 / 588 = 200 cm = 2.0 m', MetersPhrase(2)),
      (
        'television',
        1225,
        '100 * 980 / 1225 = 80 cm = 0.8 m',
        CentimetersPhrase(80),
      ),
      ('toilet', 931, '38 * 980 / 931 = 40 cm = 0.4 m', CentimetersPhrase(40)),
    ];

    test('maps every labelsV5 class width to its hand-computed phrase', () {
      expect(cases.map((c) => c.$1).toList(), hasLength(14));
      for (final (
            String label,
            double widthPx,
            String derivation,
            DistancePhrase expected,
          )
          in cases) {
        final double? meters = estimateDistanceMeters(
          label: label,
          boxWidthPx: widthPx,
        );
        expect(meters, isNotNull, reason: '$label ($derivation)');
        expect(
          distancePhrase(meters),
          expected,
          reason: '$label ($derivation)',
        );
      }
    });

    test('aliases tv and wc resolve to television and toilet', () {
      // Same widths as the television and toilet rows above.
      expect(
        distancePhrase(estimateDistanceMeters(label: 'tv', boxWidthPx: 1225)),
        CentimetersPhrase(80),
      );
      expect(
        distancePhrase(estimateDistanceMeters(label: 'wc', boxWidthPx: 931)),
        CentimetersPhrase(40),
      );
    });

    test('normalises case, padding and repeated internal whitespace', () {
      expect(
        distancePhrase(
          estimateDistanceMeters(label: '  Chair  ', boxWidthPx: 882),
        ),
        CentimetersPhrase(50),
      );
      expect(
        distancePhrase(
          estimateDistanceMeters(label: 'TELEVISION', boxWidthPx: 1225),
        ),
        CentimetersPhrase(80),
      );
      // Collapsed: "Electric   Fan" → "electric fan".
      expect(
        distancePhrase(
          estimateDistanceMeters(label: 'Electric   Fan', boxWidthPx: 980),
        ),
        CentimetersPhrase(40),
      );
      // The alias lookup happens after normalisation too.
      expect(
        distancePhrase(estimateDistanceMeters(label: ' TV ', boxWidthPx: 1225)),
        CentimetersPhrase(80),
      );
    });

    test('zero or negative width yields null', () {
      expect(estimateDistanceMeters(label: 'chair', boxWidthPx: 0), isNull);
      expect(estimateDistanceMeters(label: 'chair', boxWidthPx: -490), isNull);
    });

    test('an unknown label yields null, including the fallback label', () {
      expect(estimateDistanceMeters(label: 'unicorn', boxWidthPx: 882), isNull);
      // `Copy.objectFallback` (plan Task 2 emits it for out-of-range
      // class indices) must never receive a distance.
      expect(estimateDistanceMeters(label: 'object', boxWidthPx: 882), isNull);
      expect(estimateDistanceMeters(label: '', boxWidthPx: 882), isNull);
      expect(estimateDistanceMeters(label: '   ', boxWidthPx: 882), isNull);
    });

    test('is device-independent: same model-space width, same phrase', () {
      // The function accepts only the label and the model-space (640)
      // box width — no view or screen size can reach it — so repeated
      // calls with the same arguments must produce equal phrases.
      for (final (String label, double widthPx) in <(String, double)>[
        ('chair', 882),
        ('person', 196),
        ('tv', 1225),
      ]) {
        final DistancePhrase? first = distancePhrase(
          estimateDistanceMeters(label: label, boxWidthPx: widthPx),
        );
        for (int i = 0; i < 3; i++) {
          expect(
            distancePhrase(
              estimateDistanceMeters(label: label, boxWidthPx: widthPx),
            ),
            first,
            reason: '$label at $widthPx px must be stable',
          );
        }
      }
    });

    test('every non-null result phrases as metres or centimeters only', () {
      for (final double widthPx in <double>[1, 50, 196, 490, 882, 980, 5000]) {
        final DistancePhrase? phrase = distancePhrase(
          estimateDistanceMeters(label: 'person', boxWidthPx: widthPx),
        );
        expect(phrase, isNotNull);
        expect(
          phrase,
          anyOf(isA<MetersPhrase>(), isA<CentimetersPhrase>()),
          reason: 'widthPx $widthPx',
        );
      }
    });
  });

  group('distancePhrase', () {
    test('null metres phrasing stays null', () {
      expect(distancePhrase(null), isNull);
    });

    test('sub-metre values bucket to the nearest 10 cm', () {
      expect(distancePhrase(0.94), CentimetersPhrase(90));
      expect(distancePhrase(0.5), CentimetersPhrase(50));
    });

    test('0.96 m rounds up to the 100 cm promotion, MetersPhrase(1)', () {
      expect(distancePhrase(0.96), MetersPhrase(1));
    });

    test('0.999 m also promotes to MetersPhrase(1)', () {
      expect(distancePhrase(0.999), MetersPhrase(1));
    });

    test('tiny distances floor at 10 cm', () {
      expect(distancePhrase(0.04), CentimetersPhrase(10));
    });

    test('exactly 1.0 m is MetersPhrase(1)', () {
      expect(distancePhrase(1.0), MetersPhrase(1));
    });

    test('metres round to the nearest whole metre', () {
      expect(distancePhrase(1.4), MetersPhrase(1));
      expect(distancePhrase(1.5), MetersPhrase(2));
      expect(distancePhrase(2.0), MetersPhrase(2));
    });
  });

  group('DistancePhrase equality', () {
    test('same value and type are equal with equal hashCodes', () {
      expect(MetersPhrase(2), MetersPhrase(2));
      expect(MetersPhrase(2).hashCode, MetersPhrase(2).hashCode);
      expect(CentimetersPhrase(50), CentimetersPhrase(50));
      expect(CentimetersPhrase(50).hashCode, CentimetersPhrase(50).hashCode);
    });

    test('different values or types are not equal', () {
      expect(MetersPhrase(2), isNot(MetersPhrase(3)));
      expect(CentimetersPhrase(50), isNot(CentimetersPhrase(60)));
      expect(MetersPhrase(2), isNot(CentimetersPhrase(200)));
      expect(MetersPhrase(2), isNot(2));
    });

    test('both phrase types are const-constructible', () {
      const DistancePhrase phrase = MetersPhrase(1);
      expect(phrase, MetersPhrase(1));
      const DistancePhrase other = CentimetersPhrase(10);
      expect(other, CentimetersPhrase(10));
    });
  });
}

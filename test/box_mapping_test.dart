import 'dart:ui' show Rect, Size;

import 'package:blindspot_app/services/detection/box_mapping.dart';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapBoxToView', () {
    test('inverts the letterbox and applies the cover scale', () {
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(320, 320, 340, 340),
          frameSize: const Size(640, 480),
          viewSize: const Size(320, 240),
        ),
        rectMoreOrLessEquals(const Rect.fromLTRB(160, 120, 170, 130)),
      );
    });

    test('a 640x480 frame letterboxes the model 80 px top and bottom', () {
      // The full model maps to the padded frame, not the whole frame: the
      // 80 model-space pad rows become 40 view pixels at cover scale 0.5.
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(0, 0, 640, 640),
          frameSize: const Size(640, 480),
          viewSize: const Size(320, 240),
        ),
        rectMoreOrLessEquals(const Rect.fromLTRB(0, -40, 320, 280)),
      );
    });

    test('contain pads instead of cropping when the aspects differ', () {
      // Frame 4:3 (640x480) in a 5:4 view: contain scale 0.46875 with a
      // 7.5 px vertical offset; model y 320..340 is frame y 240..260.
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(320, 320, 340, 340),
          frameSize: const Size(640, 480),
          viewSize: const Size(300, 240),
          fit: BoxFit.contain,
        ),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(150, 120, 159.375, 129.375),
          epsilon: 1e-9,
        ),
      );
    });

    test('a portrait frame letterboxes horizontally and crops with cover', () {
      // Frame 480x640 pads x by 80 model px; cover in a 360x640 view is
      // scale 1 with a -60 px horizontal offset.
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(300, 300, 340, 340),
          frameSize: const Size(480, 640),
          viewSize: const Size(360, 640),
        ),
        rectMoreOrLessEquals(const Rect.fromLTRB(160, 300, 200, 340)),
      );
    });

    test('a square frame contains without cropping', () {
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(288, 288, 352, 352),
          frameSize: const Size(640, 640),
          viewSize: const Size(400, 300),
          fit: BoxFit.contain,
        ),
        rectMoreOrLessEquals(const Rect.fromLTRB(185, 135, 215, 165)),
      );
    });

    test('a square frame covers by cropping the vertical axis', () {
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(288, 288, 352, 352),
          frameSize: const Size(640, 640),
          viewSize: const Size(400, 300),
        ),
        // 0.625 scale makes the 640-square frame 400x400, so the 4:3 view
        // crops 50 px top and bottom: y = 288..352 maps to 130..170.
        rectMoreOrLessEquals(const Rect.fromLTRB(180, 130, 220, 170)),
      );
    });

    test('a zero-sized frame or view maps to Rect.zero, never NaN', () {
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(0, 0, 100, 100),
          frameSize: Size.zero,
          viewSize: const Size(320, 240),
        ),
        Rect.zero,
      );
      expect(
        mapBoxToView(
          modelBox: const Rect.fromLTRB(0, 0, 100, 100),
          frameSize: const Size(640, 480),
          viewSize: Size.zero,
        ),
        Rect.zero,
      );
    });
  });
}

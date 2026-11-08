/// Phase-2 detection thresholds, pinned verbatim from the plan
/// (`docs/superpowers/plans/2026-10-21-blindspot-phase2-detection.md`,
/// Task 1). Every number is either from the binding spec (§6.1/§10) or
/// from the donor code, with the deliberate deviations listed in the
/// plan's "Decisions" table.
///
/// Per `p2-global-constraints.md`, no engine, announcer, alarm or
/// overlay code may re-derive these numbers as literals — everything
/// reads them from here, and `test/detection_constants_test.dart` fails
/// if any of them moves.
abstract final class DetectionConstants {
  /// Letterboxed model input is square [inputSize] × [inputSize].
  static const int inputSize = 640;

  /// 0..255 letterbox pad grey (donor padding value).
  static const int padValue = 114;

  /// "Balanced" confidence gate (spec §6.1); the donor's 0.60.
  static const double confidenceBalanced = 0.60;

  /// Per-class NMS IoU threshold (spec §6.1); the donor's 0.50.
  static const double nmsIou = 0.50;

  /// Minimum gap between accepted frames (spec §10; donor used 450).
  static const int frameMinIntervalMs = 600;

  /// Thermal backoff tiers: 600 → [1200, 2000] ms (spec §10).
  static const List<int> thermalBackoffMs = <int>[1200, 2000];

  /// Processing slower than this counts as a "slow frame" for the
  /// thermal ladder (two consecutive slow frames escalate a tier).
  static const int thermalSlowMs = 350;

  /// Continuously fast processing for this long steps the tier back down.
  static const int thermalRecoverMs = 10000;

  /// Side length of the downsampled gray plane used by the motion gate.
  static const int motionSize = 112;

  /// Mean-absolute-difference below which a frame is "no motion" and is
  /// skipped (the first frame always passes).
  static const int motionMad = 18;

  /// Focal length in pixels for the width-based distance estimate.
  static const double focalLengthPx = 980;

  /// Proximity alarm fires strictly below this distance (spec §6.1/§10).
  static const double proximityMeters = 0.7;

  /// Vibration pulse at alarm start.
  static const int proximityVibrateMs = 300;

  /// Pause between the alarm sound and the spoken too-close warning
  /// (plan Task 8's "wait 1000 ms").
  static const int proximitySoundMs = 1000;

  /// After the alarm speech, a re-trigger inside this window is ignored.
  static const int proximityCooldownMs = 3000;

  /// Announcing a *different* label requires this much silence.
  static const int announceChangedLabelMs = 2000;

  /// Announcing the *same* label again waits a randomised
  /// [announceSameLabelMinMs]..[announceSameLabelMaxMs] ms window
  /// (spec §6.1; the donor keyed cooldowns by the full phrase).
  static const int announceSameLabelMinMs = 4000;
  static const int announceSameLabelMaxMs = 5000;

  /// Real-world width (cm) of each `labelsV5.txt` class, used by the
  /// width-based depth estimate. Keys are spelled exactly as the asset
  /// writes them: lower-case, `electric fan` with a space.
  static const Map<String, int> realWidthCm = <String, int>{
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
  };

  /// Alternate spoken labels normalised to a `realWidthCm` key before
  /// the distance estimate runs.
  static const Map<String, String> labelAliases = <String, String>{
    'tv': 'television',
    'wc': 'toilet',
  };
}

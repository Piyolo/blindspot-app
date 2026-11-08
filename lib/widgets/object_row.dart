import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../services/detection/detection_phrase.dart';
import '../theme/tokens.dart';

/// One object in the detection list: label, approximate distance and
/// direction, spoken as a single semantics label so TalkBack reads the
/// row once with everything that matters.
class ObjectRow extends StatelessWidget {
  const ObjectRow({super.key, required this.detection});

  final Detection detection;

  @override
  Widget build(BuildContext context) {
    final String subtitle = _subtitle(detection);
    return Semantics(
      container: true,
      label: '${detection.label}, $subtitle',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.crop_square,
                color: AppColors.brandLight,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detection.label, style: AppTextStyles.bodyLarge),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(Detection detection) {
    final String direction = detectionDirectionText(detection);
    final String? distance = detectionDistanceText(detection);
    return distance == null ? direction : '$distance, $direction';
  }
}

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A large, screen-reader-friendly action tile (56 dp minimum height per
/// spec §5.3, 48 dp minimum tap target) used for the top-level choices on
/// Welcome and later Home.
///
/// The height is a MINIMUM, not a fixed size: at large text scales the
/// label wraps and the tile grows instead of clipping, and the touch
/// target stays above 48 dp at every scale.
///
/// The semantics node carries [label] (and optionally [semanticsHint]);
/// the visual label is excluded from semantics so TalkBack reads the tile
/// exactly once.
class BigActionTile extends StatelessWidget {
  const BigActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.semanticsHint,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.container,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          hint: semanticsHint,
          // Keep the inner Text/Icon out of the merged node so the label
          // is not announced twice; the InkWell's tap action sits above
          // this node and survives the exclusion.
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Icon(icon, color: AppColors.brandLight, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(label, style: AppTextStyles.button),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

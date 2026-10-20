import 'package:flutter/material.dart';

import '../constants/copy.dart';
import '../theme/tokens.dart';

/// One permission on the Permissions screen: the deck title and
/// explanation, the CURRENT state as visible text (never colour/icon
/// alone), and the deck's Allow button while the permission is missing.
///
/// Semantics: the title + state are ONE TalkBack stop — `label` + `value` —
/// so focusing the card reports its state, and the node is a live region
/// so a state flip is announced the moment it happens (announcement
/// events are deprecated on Android; the live region is the reliable
/// channel, same as the field errors in [VoiceField]).
///
/// Heights are minimums, not fixed sizes: at large text scales (up to
/// 3.0x) the texts wrap and the button grows instead of clipping, and the
/// touch target stays above 48 dp at every scale.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.title,
    required this.explanation,
    required this.granted,
    required this.onRequest,
  });

  final String title;
  final String explanation;
  final bool granted;

  /// The request flow: resolves when the system dialog has settled and
  /// the screen has updated this card's state.
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    final String status =
        granted ? Copy.permissionGranted : Copy.permissionNotGranted;
    return Material(
      color: AppColors.container,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live region: TalkBack reads the state change when it
            // happens, and `value` reports the state whenever the card is
            // focused. `excludeSemantics` keeps the two visual texts out
            // of the node so the state is announced exactly once.
            Semantics(
              container: true,
              liveRegion: true,
              label: title,
              value: status,
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.section),
                  const SizedBox(height: 8),
                  // Colour reinforces but never replaces the words.
                  Text(
                    status,
                    style: AppTextStyles.status.copyWith(
                      color: granted ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(explanation, style: AppTextStyles.bodyLarge),
            if (!granted) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ElevatedButton(
                  onPressed: onRequest,
                  child: const Text(Copy.allow),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A labelled text field for the signed-out flow.
///
/// Phase 1 has no speech input (`TtsService`/`speech_to_text` land in
/// Phase 2), so [semanticsLabel] carries the deck's "tap to type" wording
/// (e.g. [Copy.loginField]) and TalkBack reads it as the field's label.
///
/// The visible [label] is rendered above the field and excluded from
/// semantics so the field is announced once, with [semanticsLabel].
/// The wrapper carries ONLY the label: it must never set `textField: true`,
/// because a flagged wrapper and the editable node underneath it become two
/// separate TalkBack stops — a dead labelled node followed by an unlabelled
/// edit box. With the plain label, semantics merge onto the editable node,
/// which then reads label + value + editable actions as a single stop.
/// [errorText] is rendered as a live-region text below the field — errors
/// are never colour-only, and TalkBack reads them when they appear even
/// where announcement events are deprecated (Android).
class VoiceField extends StatelessWidget {
  const VoiceField({
    super.key,
    required this.label,
    required this.controller,
    required this.semanticsLabel,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final String semanticsLabel;
  final bool obscure;
  final TextInputType keyboardType;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text(label, style: AppTextStyles.section),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: semanticsLabel,
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: AppTextStyles.bodyLarge,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            // Live region: TalkBack reads the field error the moment it
            // appears — announcement events are deprecated on Android, so
            // this is the reliable channel for validation feedback.
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                errorText!,
                style:
                    AppTextStyles.body.copyWith(color: AppColors.errorText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

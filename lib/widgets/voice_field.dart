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
/// [errorText] is rendered as text below the field — errors are never
/// colour-only.
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
            textField: true,
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
            Text(
              errorText!,
              style: AppTextStyles.body.copyWith(color: AppColors.errorText),
            ),
          ],
        ],
      ),
    );
  }
}

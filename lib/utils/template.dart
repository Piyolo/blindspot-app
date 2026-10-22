/// The one interpolation path for copy-deck templates (plan Task 1).
///
/// Replaces every `{key}` placeholder in [template] with `values[key]`
/// in a **single pass**, so substituted text is never re-scanned — a
/// value containing `{` stays verbatim. An unknown placeholder (or an
/// absent value) throws an [AssertionError] in debug builds and is left
/// verbatim in release, so a copy bug is loud in development and never
/// crashes a user. No other string interpolation may reach a user
/// (`p2-global-constraints.md`, "Copy only").
String fillTemplate(String template, Map<String, String> values) {
  return template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (Match match) {
    final String placeholder = match.group(0)!;
    final String key = match.group(1)!;
    final String? value = values[key];
    assert(
      value != null,
      'fillTemplate: no value supplied for $placeholder in "$template"',
    );
    // Release fallback: the placeholder comes back verbatim.
    return value ?? placeholder;
  });
}

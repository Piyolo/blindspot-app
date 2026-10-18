/// Anything that is not an ASCII digit `0-9`.
///
/// Deliberately not a Unicode-aware pattern — see the parity contract on
/// [normalizeContactNumber].
final RegExp _nonDigit = RegExp(r'[^0-9]');

final RegExp _asciiLetter = RegExp(r'[A-Za-z]');

final RegExp _asciiDigit = RegExp(r'[0-9]');

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns the canonical contact form: optional leading `+` followed by
/// ASCII digits only (formatting, letters, and non-ASCII digits stripped).
///
/// Mirrors the server's `normalize_contact_number` (`backend/app/schemas.py`)
/// exactly, per the parity contract: a leading `+` is kept, only ASCII
/// digits `[0-9]` count, everything else is stripped — so non-ASCII digits
/// (fullwidth `０９１７…`, Arabic-Indic `٠٩١٧…`, …) normalize away and fail
/// the 7-15 digit check instead of being stored. The server folds the
/// digit-count check into its normalizer (raising a 400); the client
/// splits it into this function plus [isValidContactNumber], which agree
/// with the server on both the accept/reject decision and the canonical
/// form.
String normalizeContactNumber(String raw) {
  final text = raw.trim();
  final digits = text.replaceAll(_nonDigit, '');
  return text.startsWith('+') ? '+$digits' : digits;
}

/// True when [raw] yields 7-15 ASCII digits after normalization — the
/// server rejects anything outside that range with `Copy.contactInvalid`.
bool isValidContactNumber(String raw) {
  final digits = raw.trim().replaceAll(_nonDigit, '');
  return digits.length >= 7 && digits.length <= 15;
}

/// True when the password is at least 8 characters with a letter and a
/// digit.
///
/// ASCII-strict where the server's `is_valid_password` uses Unicode-aware
/// `isalpha`/`isdigit`, so the client accepts only a subset of what the
/// server accepts — a password that passes here never trips the server's
/// password rule. Length counts code points (like Python's `len()`), not
/// UTF-16 units, so an astral character counts once on both sides.
bool isValidPassword(String raw) =>
    raw.runes.length >= 8 &&
    _asciiLetter.hasMatch(raw) &&
    _asciiDigit.hasMatch(raw);

/// Lightweight format check for pre-submit validation; the server's
/// `EmailStr` remains the authority.
bool isValidEmail(String raw) => _email.hasMatch(raw);

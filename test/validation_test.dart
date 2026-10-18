import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/services/validation.dart';

void main() {
  group('normalizeContactNumber', () {
    test('strips spaces and dashes', () {
      expect(normalizeContactNumber('0917 123 4567'), '09171234567');
      expect(normalizeContactNumber('+63 917-123-4567'), '+639171234567');
      expect(normalizeContactNumber('0917-123-4567'), '09171234567');
    });

    test('trims surrounding whitespace and ignores non-digit noise', () {
      expect(normalizeContactNumber(' 0917-123-4567 '), '09171234567');
      expect(normalizeContactNumber('abc09171234567'), '09171234567');
      // Lenient cases ratified from the server's normalizer (parity).
      expect(normalizeContactNumber('12+34567'), '1234567');
      expect(normalizeContactNumber('++639171234567'), '+639171234567');
    });

    test('non-ASCII digits normalize away (ASCII-only, mirrors app/schemas.py)',
        () {
      // Fullwidth digits (０９１７…).
      expect(normalizeContactNumber('０９１７１２３４５６７'), '');
      // Arabic-Indic digits (٠٩١٧…).
      expect(normalizeContactNumber('٠٩١٧١٢٣٤٥٦٧'), '');
      // Extended Arabic-Indic digits (۰۹۱۷…).
      expect(normalizeContactNumber('۰۹۱۷۱۲۳۴۵۶۷'), '');
      // A leading + survives even when the digits do not.
      expect(normalizeContactNumber('+６３９１７'), '+');
      // Mixed ASCII + non-ASCII: only the ASCII digits count (server Info note).
      expect(normalizeContactNumber('0917123４５６７'), '0917123');
    });
  });

  group('isValidContactNumber', () {
    test('accepts 7 to 15 digits in lenient formats', () {
      expect(isValidContactNumber('0917 123 4567'), isTrue);
      expect(isValidContactNumber('+63 917-123-4567'), isTrue);
      expect(isValidContactNumber('0917-123-4567'), isTrue);
      expect(isValidContactNumber('1234567'), isTrue);
      expect(isValidContactNumber('123456789012345'), isTrue);
    });

    test('rejects fewer than 7 or more than 15 digits', () {
      expect(isValidContactNumber('123'), isFalse);
      expect(isValidContactNumber('12345678901234567'), isFalse);
      expect(isValidContactNumber('123456'), isFalse);
      expect(isValidContactNumber('1234567890123456'), isFalse);
      expect(isValidContactNumber(''), isFalse);
      expect(isValidContactNumber('+'), isFalse);
      expect(isValidContactNumber('abc'), isFalse);
    });

    test('rejects numbers built only from non-ASCII digits', () {
      expect(isValidContactNumber('０９１７１２３４５６７'), isFalse);
      expect(isValidContactNumber('٠٩١٧١٢٣٤٥٦٧'), isFalse);
      expect(isValidContactNumber('۰۹۱۷۱۲۳۴۵۶۷'), isFalse);
    });
  });

  group('isValidPassword', () {
    test('rejects the pinned failing cases', () {
      expect(isValidPassword('short1'), isFalse);
      expect(isValidPassword('allletters'), isFalse);
      expect(isValidPassword('12345678'), isFalse);
    });

    test('requires at least 8 characters with a letter and a digit', () {
      expect(isValidPassword('abc1234'), isFalse);
      expect(isValidPassword('abc12345'), isTrue);
      expect(isValidPassword('abcdefgh1'), isTrue);
      expect(isValidPassword(''), isFalse);
    });
  });

  group('isValidEmail', () {
    test('accepts ordinary addresses', () {
      expect(isValidEmail('ana@example.com'), isTrue);
      expect(isValidEmail('user.name+tag@sub.domain.ph'), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('ana'), isFalse);
      expect(isValidEmail('ana@'), isFalse);
      expect(isValidEmail('@example.com'), isFalse);
      expect(isValidEmail('ana@@example.com'), isFalse);
      expect(isValidEmail('a b@c.com'), isFalse);
      expect(isValidEmail('ana@example'), isFalse);
    });
  });
}

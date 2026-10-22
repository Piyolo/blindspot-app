import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/utils/template.dart';

/// The Phase-2 template helper (plan Task 1): every `{key}` placeholder is
/// filled from the map, in a single pass over the template, so substituted
/// values are never re-scanned for placeholders.
void main() {
  group('fillTemplate', () {
    test('fills a single placeholder', () {
      expect(
        fillTemplate('{object} {direction}, {distance}', <String, String>{
          'object': 'chair',
          'direction': 'on the left',
          'distance': 'approximately 2 meters',
        }),
        'chair on the left, approximately 2 meters',
      );
    });

    test('replaces every occurrence of a repeated placeholder', () {
      expect(
        fillTemplate('{count} then {count}', <String, String>{'count': '3'}),
        '3 then 3',
      );
    });

    test('is repeatable: the same fill run twice gives the same string', () {
      const String template = '{object} {distance}';
      const Map<String, String> values = <String, String>{
        'object': 'door',
        'distance': 'approximately 2 meters',
      };
      final String first = fillTemplate(template, values);
      expect(fillTemplate(template, values), first);
      // A filled result can also be fed in as a value to a later fill.
      expect(
        fillTemplate('meters: {value}', <String, String>{'value': first}),
        'meters: door approximately 2 meters',
      );
    });

    test('an unknown placeholder asserts in debug builds', () {
      // This suite runs with asserts enabled, so the debug path is what is
      // observable here; in release the assert is stripped and `{nope}`
      // comes back verbatim (the implementation's `?? placeholder` fallthrough).
      expect(
        () => fillTemplate('a {nope} b', const <String, String>{'a': 'x'}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('an empty map leaves a placeholder-less template untouched', () {
      expect(
        fillTemplate('no placeholders here', const <String, String>{}),
        'no placeholders here',
      );
    });

    test('an empty map still asserts when the template has placeholders', () {
      expect(
        () => fillTemplate('{object}', const <String, String>{}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a value containing { is inserted verbatim, never re-expanded', () {
      expect(
        fillTemplate('{a} {b}', const <String, String>{'a': '{b}', 'b': 'x'}),
        '{b} x',
      );
    });

    test('ignores values the template does not mention', () {
      expect(
        fillTemplate('plain text', const <String, String>{'unused': 'x'}),
        'plain text',
      );
    });
  });
}

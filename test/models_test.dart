import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/constants/api_paths.dart';
import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/auth_result.dart';
import 'package:blindspot_app/models/user.dart';

void main() {
  group('User', () {
    test('fromJson parses backend field names including ISO-8601 created_at', () {
      final user = User.fromJson(const <String, dynamic>{
        'id': 7,
        'name': 'Ana Cruz',
        'email': 'ana@example.com',
        'contact_number': '09171234567',
        'created_at': '2026-10-18T09:30:00Z',
      });
      expect(user.id, 7);
      expect(user.name, 'Ana Cruz');
      expect(user.email, 'ana@example.com');
      expect(user.contactNumber, '09171234567');
      expect(user.createdAt, DateTime.parse('2026-10-18T09:30:00Z'));
    });

    test('toJson uses the API field names and round-trips through fromJson', () {
      const raw = <String, dynamic>{
        'id': 7,
        'name': 'Ana Cruz',
        'email': 'ana@example.com',
        'contact_number': '09171234567',
        'created_at': '2026-10-18T09:30:00Z',
      };
      final json = User.fromJson(raw).toJson();
      expect(json, <String, dynamic>{
        'id': 7,
        'name': 'Ana Cruz',
        'email': 'ana@example.com',
        'contact_number': '09171234567',
        'created_at': '2026-10-18T09:30:00.000Z',
      });
      // Persistable and re-readable: the persisted shape is stable.
      expect(User.fromJson(json).toJson(), json);
    });

    test('created_at with a UTC offset survives the persist round-trip', () {
      final user = User.fromJson(const <String, dynamic>{
        'id': 1,
        'name': 'Bea',
        'email': 'bea@example.com',
        'contact_number': '+639171234567',
        'created_at': '2026-10-18T17:30:00+08:00',
      });
      final persisted = user.toJson();
      final reloaded = User.fromJson(persisted);
      expect(reloaded.createdAt, user.createdAt);
      expect(reloaded.toJson(), persisted);
    });
  });

  group('AuthResult', () {
    test('fromJson reads access_token and the nested user', () {
      final result = AuthResult.fromJson(const <String, dynamic>{
        'access_token': 'jwt-token-value',
        'token_type': 'bearer',
        'user': <String, dynamic>{
          'id': 3,
          'name': 'Ana',
          'email': 'ana@example.com',
          'contact_number': '09171234567',
          'created_at': '2026-10-18T09:30:00Z',
        },
      });
      expect(result.accessToken, 'jwt-token-value');
      expect(result.user.id, 3);
      expect(result.user.name, 'Ana');
      expect(result.user.email, 'ana@example.com');
      expect(result.user.contactNumber, '09171234567');
      expect(result.user.createdAt, DateTime.parse('2026-10-18T09:30:00Z'));
    });
  });

  group('ApiPaths', () {
    test('paths match the deployed API routes', () {
      expect(ApiPaths.signup, '/auth/signup');
      expect(ApiPaths.login, '/auth/login');
      expect(ApiPaths.me, '/me');
      expect(ApiPaths.mePassword, '/me/password');
    });
  });

  group('Copy', () {
    test('ruling-pinned keys are verbatim in both languages', () {
      expect(Copy.contactInvalid,
          'Enter a valid contact number (7 to 15 digits).');
      expect(CopyFil.contactInvalid,
          'Maglagay ng tamang contact number (7 hanggang 15 na numero).');
      expect(Copy.genericError, 'Something went wrong. Please try again.');
      expect(CopyFil.genericError, 'May problema. Subukan ulit.');
    });

    test('spec §11 keys are verbatim in both languages', () {
      expect(Copy.loginError, 'Invalid email or password.');
      expect(CopyFil.loginError, 'Mali ang email o password.');
      expect(Copy.passwordChanged, 'Password changed.');
      expect(CopyFil.passwordChanged, 'Nabago na ang password.');
      expect(Copy.serverWaking, 'The server is waking up. One moment.');
      expect(CopyFil.serverWaking, 'Nagigising pa ang server. Sandali lang.');
    });

    test('signedInAs interpolates the name in both languages', () {
      expect(Copy.signedInAs('Ana'), 'Signed in as Ana.');
      expect(CopyFil.signedInAs('Ana'), 'Naka-log in bilang Ana.');
    });
  });
}

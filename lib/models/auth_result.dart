import 'package:blindspot_app/models/user.dart';

/// Successful signup/login payload from the API's `TokenResponse`
/// (`access_token`, `token_type`, `user`); `token_type` is always
/// `"bearer"` and is not stored.
class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.user,
  });

  final String accessToken;
  final User user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );
}

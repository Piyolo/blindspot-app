/// API route paths, relative to `ApiClient`'s `/api/v1` base prefix.
class ApiPaths {
  const ApiPaths._();

  static const String signup = '/auth/signup';
  static const String login = '/auth/login';
  static const String me = '/me';
  static const String mePassword = '/me/password';
}

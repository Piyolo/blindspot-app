import 'package:permission_handler/permission_handler.dart';

/// The three system permissions Phase 1 asks for, named for the app layer
/// so screens never import `permission_handler` directly.
enum AppPermission { microphone, camera, phone }

/// Abstraction over the platform permission prompts so screens never touch
/// `permission_handler` (or its platform channels) directly, and tests run
/// against [FakePermissionsService] with no platform involvement.
abstract class PermissionsService {
  /// Reads the CURRENT state — never prompts.
  Future<bool> isGranted(AppPermission p);

  /// Requests [p] from the system (may prompt the user) and returns the
  /// resulting state.
  Future<bool> request(AppPermission p);
}

/// Production service backed by `permission_handler`.
class PermissionHandlerService implements PermissionsService {
  const PermissionHandlerService();

  static Permission _platform(AppPermission p) {
    switch (p) {
      case AppPermission.microphone:
        return Permission.microphone;
      case AppPermission.camera:
        return Permission.camera;
      case AppPermission.phone:
        return Permission.phone;
    }
  }

  @override
  Future<bool> isGranted(AppPermission p) async =>
      (await _platform(p).status).isGranted;

  @override
  Future<bool> request(AppPermission p) async =>
      (await _platform(p).request()).isGranted;
}

/// Test double: configurable initial states and request outcomes, headless
/// — no platform channels. [reads] and [requests] record every call so a
/// test can prove a screen only ever reads on entry and requests exactly
/// what the user asked for.
class FakePermissionsService implements PermissionsService {
  FakePermissionsService({
    Map<AppPermission, bool> granted = const <AppPermission, bool>{},
    Map<AppPermission, bool> requestOutcomes = const <AppPermission, bool>{},
  })  : _granted = Map<AppPermission, bool>.of(granted),
        _requestOutcomes = Map<AppPermission, bool>.of(requestOutcomes);

  final Map<AppPermission, bool> _granted;

  /// What `request()` answers for each permission; defaults to granted.
  final Map<AppPermission, bool> _requestOutcomes;

  /// Every state read this fake has served, in order.
  final List<AppPermission> reads = <AppPermission>[];

  /// Every request this fake has served, in order.
  final List<AppPermission> requests = <AppPermission>[];

  @override
  Future<bool> isGranted(AppPermission p) async {
    reads.add(p);
    return _granted[p] ?? false;
  }

  @override
  Future<bool> request(AppPermission p) async {
    requests.add(p);
    final bool outcome = _requestOutcomes[p] ?? true;
    _granted[p] = outcome;
    return outcome;
  }
}

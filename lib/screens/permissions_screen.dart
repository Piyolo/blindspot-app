import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../constants/copy.dart';
import '../services/permissions_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/permission_card.dart';

/// Post-signup/signin permissions step: one card per system permission
/// (microphone, camera, phone) with the deck's explanation and Allow
/// button, plus Continue to `/home`.
///
/// Entering the screen only READS state — a system prompt without a user
/// gesture is never acceptable. Each Allow requests just that permission
/// and updates just that card, without leaving the screen. With all three
/// granted the deck's all-set copy replaces the denied states; with any
/// missing, Continue still works but first announces the limited-mode
/// copy, so a blind user hears what they are giving up.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.service});

  /// Test seam: production leaves this null and the screen runs the live
  /// [PermissionHandlerService].
  final PermissionsService? service;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late final PermissionsService _service;

  /// Starts denied; the reads in [_load] replace each entry with the real
  /// state. A read that fails (permission plugin unavailable) counts as
  /// denied — the screen must never crash the flow.
  final Map<AppPermission, bool> _granted = <AppPermission, bool>{
    for (final AppPermission p in AppPermission.values) p: false,
  };

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? const PermissionHandlerService();
    _load();
  }

  /// Reads all three states — never requests. Each read is independent,
  /// so a failure on one still lets the others report.
  Future<void> _load() async {
    final bool microphone = await _read(AppPermission.microphone);
    final bool camera = await _read(AppPermission.camera);
    final bool phone = await _read(AppPermission.phone);
    if (!mounted) {
      return;
    }
    setState(() {
      _granted[AppPermission.microphone] = microphone;
      _granted[AppPermission.camera] = camera;
      _granted[AppPermission.phone] = phone;
    });
  }

  Future<bool> _read(AppPermission p) async {
    try {
      return await _service.isGranted(p);
    } catch (_) {
      // A broken plugin reads as denied; the user can still continue.
      return false;
    }
  }

  /// Requests one permission and updates that one card in place; never
  /// navigates and never re-reads the others.
  Future<void> _request(AppPermission p) async {
    bool granted = false;
    try {
      granted = await _service.request(p);
    } catch (_) {
      // A failed request leaves the card denied, not the screen broken.
    }
    if (!mounted) {
      return;
    }
    setState(() => _granted[p] = granted);
  }

  bool get _allGranted =>
      AppPermission.values.every((AppPermission p) => _granted[p] == true);

  /// Continue always reaches `/home`; when permissions are missing the
  /// limited-mode copy is announced first (awaited, so TalkBack has it
  /// before the route changes). The announcement is best-effort — an
  /// announcement failure must never block navigation.
  Future<void> _continue() async {
    if (!_allGranted) {
      try {
        await SemanticsService.sendAnnouncement(
          View.of(context),
          Copy.limitedMode,
          Directionality.of(context),
        );
      } catch (_) {
        // Best-effort by design, like the login/signup announcements.
      }
    }
    if (!mounted) {
      return;
    }
    // Replace, not push: back from Home must not return to Permissions.
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The shared dark status-bar style, as on the other AppBar-less
      // screens (see [AppTheme.statusBarStyle]).
      value: AppTheme.statusBarStyle,
      child: Scaffold(
        appBar: AppBar(title: const Text(Copy.permissionsTitle)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_allGranted) ...[
                  // Live region: the all-set state is announced the moment
                  // the last permission lands, not only read on focus.
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: const Text(
                      Copy.allSet,
                      style: AppTextStyles.status,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                PermissionCard(
                  title: Copy.microphoneLabel,
                  explanation: Copy.micPermission,
                  granted: _granted[AppPermission.microphone]!,
                  onRequest: () => _request(AppPermission.microphone),
                ),
                const SizedBox(height: 16),
                PermissionCard(
                  title: Copy.cameraLabel,
                  explanation: Copy.cameraPermission,
                  granted: _granted[AppPermission.camera]!,
                  onRequest: () => _request(AppPermission.camera),
                ),
                const SizedBox(height: 16),
                PermissionCard(
                  title: Copy.phoneLabel,
                  explanation: Copy.phonePermission,
                  granted: _granted[AppPermission.phone]!,
                  onRequest: () => _request(AppPermission.phone),
                ),
                const SizedBox(height: 24),
                // 56 dp minimum (spec §5.3); the label wraps and the
                // button grows at large text scales instead of clipping.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton(
                    onPressed: _continue,
                    child: const Text(Copy.continueLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/copy.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../services/validation.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/big_action_tile.dart';
import '../widgets/voice_field.dart';

/// The signed-in account screen: the name/email readout, the editable
/// emergency contact number (Save), the change-password form, and Log out.
///
/// Every string comes from the copy deck, and every state change has two
/// announcement sources — a live region on the visible text and a
/// best-effort `SemanticsService.sendAnnouncement` — because TalkBack is
/// the primary interface (announcement events are deprecated on Android,
/// so the live region is the reliable channel and the announcement is the
/// secondary one).
///
/// The two provider error surfaces follow the provider's own mapping:
/// - An edit that the server rejects with a 401 that is NOT the dedicated
///   wrong-current-password detail is a dead session: `ProfileProvider`
///   delegates to `AuthProvider.handleUnauthorized`, which clears the
///   session and deliberately leaves `lastError` null. This screen
///   sources its one-time [Copy.loginError] notice from that status
///   transition and clears the whole stack into `/welcome`, so back
///   cannot return to a signed-in screen.
/// - A network-level failure (`statusCode == null`) maps to
///   [Copy.needInternet]; the edit did not take, so the contact field
///   goes back to the cached user's value instead of pretending the new
///   one was saved.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  late final AuthProvider _auth;
  late final ProfileProvider _profile;

  /// True from the moment this screen knows it is leaving for `/welcome` —
  /// either the session died (a 401 on any profile call) or the user
  /// chose Log out. Set synchronously before any await, so the
  /// dead-session notice fires exactly once and the logout dialog's own
  /// routing is never doubled by the status watcher below.
  bool _leaving = false;

  /// Whether the screen opened on a live session. Routing guarantees a
  /// signed-in user; a route-table push without a session (or a restore
  /// race) mounts the screen already signed out, and that state must
  /// never be mistaken for a 401 transition.
  late final bool _openedSignedIn;

  String? _contactError;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;

  /// Per-section result line (confirmation or provider failure), rendered
  /// in a live region and announced. Field-level validation errors stay
  /// on their [VoiceField] instead.
  ({String text, bool isError})? _contactStatus;
  ({String text, bool isError})? _passwordStatus;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _profile = context.read<ProfileProvider>();
    _openedSignedIn = _auth.status == AuthStatus.signedIn;
    // A failure from a previous screen (e.g. a failed login) must never
    // render as a live-region error here (the Task 9 ruling).
    _auth.clearError();
    _contact.text = _auth.user?.contactNumber ?? '';
    _auth.addListener(_onAuthChanged);
    _profile.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _profile.removeListener(_onProfileChanged);
    _contact.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) {
      return;
    }
    if (_openedSignedIn && _auth.status == AuthStatus.signedOut && !_leaving) {
      // The only way here is a server-side 401 on a profile call:
      // ProfileProvider delegated to AuthProvider.handleUnauthorized.
      unawaited(_leaveAfterSessionExpired());
      return;
    }
    setState(() {});
  }

  void _onProfileChanged() {
    if (!mounted) {
      return;
    }
    // `busy` flips: the Save / Change password buttons must disable for
    // the in-flight window, exactly like the auth screens.
    setState(() {});
  }

  /// A 401 means the session itself is dead: announce [Copy.loginError]
  /// exactly once (the [_leaving] flag is set synchronously, before the
  /// awaited announcement) and clear the whole stack into `/welcome`, so
  /// back cannot return to a signed-in-looking screen.
  Future<void> _leaveAfterSessionExpired() async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    try {
      await SemanticsService.sendAnnouncement(
        View.of(context),
        Copy.loginError,
        Directionality.of(context),
      );
    } catch (_) {
      // Best-effort: an announcement failure must never block the route.
    }
    if (!mounted) {
      return;
    }
    _exitToWelcome();
  }

  /// The one way off this screen toward Welcome: removes EVERY route
  /// before pushing `/welcome`, so back from Welcome can never return to
  /// a zombie Home whose Profile tile would open a sessionless screen
  /// (F2 — a plain `pushReplacementNamed` would leave Home beneath
  /// Welcome). Used by both exits: logout and the dead-session 401.
  void _exitToWelcome() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/welcome', (Route<dynamic> route) => false);
  }

  /// Announces [message] as a best-effort secondary signal. The primary
  /// channel is the live region on the visible text: Android has deprecated
  /// announcement events, so TalkBack on modern Android may ignore them
  /// entirely. An announcement failure must never fail the screen action
  /// it accompanies, so errors are swallowed.
  Future<void> _announce(String message) async {
    try {
      await SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    } catch (_) {
      // Best-effort by design: the live region already carries the message.
    }
  }

  Future<void> _saveContact() async {
    if (_profile.busy) {
      return;
    }
    final String raw = _contact.text;
    // Validation before anything reaches the repository — the same
    // accept/reject decision and canonical form the server makes
    // (see [isValidContactNumber] / [normalizeContactNumber]).
    final String? fieldError = isValidContactNumber(raw)
        ? null
        : Copy.contactInvalid;
    // A double-tap on the same invalid input does not make TalkBack read
    // the same sentence twice: announce only on an error transition.
    final bool errorChanged = _contactError != fieldError;
    setState(() {
      _contactError = fieldError;
      // A new attempt supersedes the previous result line.
      _contactStatus = null;
    });
    if (fieldError != null) {
      if (errorChanged) {
        await _announce(fieldError);
      }
      return;
    }
    final bool ok = await _profile.updateContact(normalizeContactNumber(raw));
    if (!mounted) {
      return;
    }
    if (_leaving) {
      // A 401 already routed this screen away; nothing else to report.
      return;
    }
    if (ok) {
      setState(() {
        // The displayed value follows the provider's refreshed user, not
        // the raw text that was typed.
        _contact.text =
            _auth.user?.contactNumber ?? normalizeContactNumber(raw);
        _contactStatus = (text: Copy.savedContact, isError: false);
      });
      await _announce(Copy.savedContact);
      return;
    }
    final String? failure = _profile.lastError;
    if (failure == null) {
      // The busy guard swallowed the call, or the session died mid-flight;
      // either way there is nothing new to show.
      return;
    }
    // The edit did not take: the displayed value stays the cached one.
    setState(() {
      _contact.text = _auth.user?.contactNumber ?? _contact.text;
      _contactStatus = (text: failure, isError: true);
    });
    await _announce(failure);
  }

  Future<void> _changePassword() async {
    if (_profile.busy) {
      return;
    }
    final String current = _currentPassword.text;
    final String next = _newPassword.text;
    final String? currentError = current.isEmpty ? Copy.passwordRequired : null;
    final String? nextError = isValidPassword(next) ? null : Copy.passwordRule;
    // A mismatch gets its own copy — it is not a rule failure — shown on
    // the confirm field, where the fix belongs.
    final String? confirmError;
    if (nextError != null || _confirmPassword.text == next) {
      confirmError = null;
    } else {
      confirmError = Copy.passwordMismatch;
    }
    final String? firstError = currentError ?? nextError ?? confirmError;
    final bool errorChanged =
        _currentPasswordError != currentError ||
        _newPasswordError != nextError ||
        _confirmPasswordError != confirmError;
    setState(() {
      _currentPasswordError = currentError;
      _newPasswordError = nextError;
      _confirmPasswordError = confirmError;
      _passwordStatus = null;
    });
    if (firstError != null) {
      if (errorChanged) {
        await _announce(firstError);
      }
      return;
    }
    final bool ok = await _profile.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    if (!mounted) {
      return;
    }
    if (_leaving) {
      return;
    }
    if (ok) {
      setState(() {
        _currentPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
        _currentPasswordError = null;
        _newPasswordError = null;
        _confirmPasswordError = null;
        _passwordStatus = (text: Copy.passwordChanged, isError: false);
      });
      await _announce(Copy.passwordChanged);
      return;
    }
    final String? failure = _profile.lastError;
    if (failure == null) {
      return;
    }
    // Includes the dedicated wrong-current-password copy: a rejected
    // edit, not a dead session — the fields keep their values so only
    // the current password needs fixing.
    setState(() => _passwordStatus = (text: failure, isError: true));
    await _announce(failure);
  }

  Future<void> _confirmLogout() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            content: const Text(Copy.logoutConfirm),
            actions: [
              // 48 dp minimum per the global a11y constraint; the labels
              // grow instead of clipping at large text scales.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(Copy.no),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(Copy.yes),
                ),
              ),
            ],
          ),
        ) ??
        false; // barrier dismiss counts as "No": nothing changes
    if (!mounted || !confirmed) {
      return;
    }
    // Flag first: signOut() notifies listeners synchronously, and the
    // status watcher must not treat this user-chosen sign-out as a 401.
    _leaving = true;
    await _auth.signOut();
    if (!mounted) {
      return;
    }
    _exitToWelcome();
  }

  Widget _statusLine(({String text, bool isError}) status) => Semantics(
    // Live region: the result is announced the moment it appears, not
    // only read on focus.
    container: true,
    liveRegion: true,
    child: Text(
      status.text,
      style: status.isError
          ? AppTextStyles.body.copyWith(color: AppColors.errorText)
          : AppTextStyles.status,
    ),
  );

  /// Label + value as ONE semantics node, so TalkBack reads the readout as
  /// a single stop ("Your name, Ana Cruz") instead of a dead label beside
  /// an unlabelled value. Not editable: only the contact number and the
  /// password fields are, by design.
  Widget _readout(String label, String value) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.section),
        Text(value, style: AppTextStyles.bodyLarge),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final User? user = _auth.user;
    // The shared dark status-bar style, as on the other screens (see
    // [AppTheme.statusBarStyle]).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.statusBarStyle,
      child: Scaffold(
        appBar: AppBar(title: const Text(Copy.profileTitle)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (user != null) ...[
                  _readout(Copy.nameLabel, user.name),
                  const SizedBox(height: 16),
                  // Email is read-only: rendered, never editable.
                  _readout(Copy.emailLabel, user.email),
                  const SizedBox(height: 16),
                ],
                VoiceField(
                  label: Copy.contactNumberLabel,
                  semanticsLabel: Copy.emergencyNumberField,
                  controller: _contact,
                  keyboardType: TextInputType.phone,
                  errorText: _contactError,
                ),
                if (_contactStatus != null) ...[
                  _statusLine(_contactStatus!),
                  const SizedBox(height: 16),
                ],
                // 56 dp is a minimum height, not a fixed size: at large
                // text scales the label lays out fully and the control
                // grows instead of clipping.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton(
                    onPressed: _profile.busy ? null : _saveContact,
                    child: const Text(Copy.save),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  // A navigable, non-interactive section heading for
                  // TalkBack (F4): the action button below keeps its own
                  // label and button semantics, so the heading is never
                  // announced as a button.
                  header: true,
                  child: const Text(
                    Copy.changePasswordLabel,
                    style: AppTextStyles.section,
                  ),
                ),
                const SizedBox(height: 8),
                VoiceField(
                  label: Copy.currentPasswordLabel,
                  semanticsLabel: Copy.currentPasswordLabel,
                  controller: _currentPassword,
                  obscure: true,
                  errorText: _currentPasswordError,
                ),
                VoiceField(
                  label: Copy.newPasswordLabel,
                  semanticsLabel: Copy.newPasswordLabel,
                  controller: _newPassword,
                  obscure: true,
                  errorText: _newPasswordError,
                ),
                VoiceField(
                  label: Copy.confirmPasswordLabel,
                  semanticsLabel: Copy.confirmPasswordField,
                  controller: _confirmPassword,
                  obscure: true,
                  errorText: _confirmPasswordError,
                ),
                if (_passwordStatus != null) ...[
                  _statusLine(_passwordStatus!),
                  const SizedBox(height: 16),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton(
                    onPressed: _profile.busy ? null : _changePassword,
                    child: const Text(Copy.changePasswordLabel),
                  ),
                ),
                const SizedBox(height: 24),
                // BigActionTile carries the button semantics and the 56 dp
                // minimum height.
                BigActionTile(
                  label: Copy.logOut,
                  icon: Icons.logout,
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

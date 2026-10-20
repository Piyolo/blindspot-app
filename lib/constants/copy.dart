/// The complete Phase-1 copy deck (spec §11 + pinned Phase-1 additions).
///
/// Data only — no logic beyond the interpolation helpers. Every
/// user-facing string rendered in Phase 1 must come from here; no screen
/// may contain a bare string literal for copy. Adding a key requires a
/// plan amendment.
///
/// [Copy] holds the English strings, which are the Phase-1 default UI
/// language. [CopyFil] mirrors every key verbatim in Filipino (spec §11's
/// first pass, due a native-speaker review with the user in Phase 5).
/// Key names are identical in both classes.
class Copy {
  const Copy._();

  // --- Spec §11 (EN/FIL pairs) ---

  static const String boot = 'BlindSpot is starting.';
  static const String welcome =
      'Welcome to BlindSpot. You can log in, sign up, or ask a trusted person for setup help.';
  static const String loginField =
      'Email field. Speak your email or tap to type.';
  static const String passwordField =
      'Password field. Characters are hidden.';
  static const String passwordRule =
      'Password must be at least 8 characters with a letter and a number.';
  static const String emergencyNumberField =
      'Mobile number field. Tap to type, or speak it, starting with zero nine, or plus six three.';
  static const String micPermission =
      'BlindSpot needs the microphone to hear your voice commands.';
  static const String cameraPermission =
      'BlindSpot needs the camera to detect objects around you.';
  static const String phonePermission =
      'BlindSpot needs phone access to call your emergency contact.';
  static const String home =
      'Home. Object detection and voice commands are coming in a later update. For now, choose Profile.';
  static const String loginError = 'Invalid email or password.';
  static const String emailExists =
      'This email is already registered. Try logging in.';
  static const String offline = 'No internet connection.';
  static const String serverWaking = 'The server is waking up. One moment.';
  static const String logoutConfirm =
      'Log out? You will need to sign in again.';
  static const String passwordChanged = 'Password changed.';
  static const String wrongCurrentPassword =
      'Current password is incorrect.';

  // --- Phase-1 additions (pinned; folded into spec §11 in Phase 5) ---

  static const String logIn = 'Log in';
  static const String signUp = 'Sign up';
  static const String profileTitle = 'Profile';
  static const String permissionsTitle = 'Permissions';
  static const String save = 'Save';
  static const String logOut = 'Log out';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String continueLabel = 'Continue';
  static const String allSet = 'All set. Continue.';
  static const String limitedMode =
      'Continuing without some permissions. Some features will not work.';
  static const String needInternet = 'You need internet to change this.';
  static const String rateLimited =
      'Too many attempts. Try again later.';
  static const String nameLabel = 'Your name';
  static const String emailLabel = 'Email address';
  static const String contactNumberLabel = 'Emergency contact number';
  static const String currentPasswordLabel = 'Current password';
  static const String newPasswordLabel = 'New password';
  static const String changePasswordLabel = 'Change password';
  static const String savedContact = 'Contact number saved.';
  static const String allow = 'Allow';
  static const String contactInvalid =
      'Enter a valid contact number (7 to 15 digits).';
  static const String genericError =
      'Something went wrong. Please try again.';
  static const String passwordLabel = 'Password';
  static const String confirmPasswordLabel = 'Confirm password';
  static const String confirmPasswordField =
      'Confirm password field. Characters are hidden.';
  static const String passwordMismatch = 'The passwords do not match.';
  static const String emailInvalid = 'Enter a valid email address.';
  static const String passwordRequired = 'Enter your password.';
  static const String microphoneLabel = 'Microphone';
  static const String cameraLabel = 'Camera';
  static const String phoneLabel = 'Phone';
  static const String permissionGranted = 'Allowed';
  static const String permissionNotGranted = 'Not allowed';

  /// The one interpolation helper: `Signed in as {name}.`
  static String signedInAs(String name) => 'Signed in as $name.';
}

/// Filipino mirror of [Copy] — same keys, verbatim spec §11 FIL strings.
class CopyFil {
  const CopyFil._();

  // --- Spec §11 (EN/FIL pairs) ---

  static const String boot = 'Nagsisimula ang BlindSpot.';
  static const String welcome =
      'Maligayang pagdating sa BlindSpot. Pwede kang mag-log in, mag-sign up, o humingi ng tulong sa pinagkakatiwalaan mong tao para sa setup.';
  static const String loginField =
      'Email field. Sabihin ang iyong email o pindutin para mag-type.';
  static const String passwordField =
      'Password field. Nakatago ang mga karakter.';
  static const String passwordRule =
      'Ang password ay dapat hindi bababa sa 8 karakter, at may titik at numero.';
  static const String emergencyNumberField =
      'Mobile number field. Pindutin para mag-type, o sabihin, simula sa zero nine, o plus six three.';
  static const String micPermission =
      'Kailangan ng BlindSpot ang mikropono para marinig ang iyong mga utos.';
  static const String cameraPermission =
      'Kailangan ng BlindSpot ang kamera para matukoy ang mga bagay sa paligid mo.';
  static const String phonePermission =
      'Kailangan ng BlindSpot ang akses sa telepono para matawagan ang emergency contact mo.';
  static const String home =
      'Home. Paparating na ang object detection at voice commands sa susunod na update. Sa ngayon, piliin ang Profile.';
  static const String loginError = 'Mali ang email o password.';
  static const String emailExists =
      'Nakarehistro na ang email na ito. Subukang mag-log in.';
  static const String offline = 'Walang koneksyon sa internet.';
  static const String serverWaking = 'Nagigising pa ang server. Sandali lang.';
  static const String logoutConfirm =
      'Mag-log out? Kailangan mong mag-log in muli.';
  static const String passwordChanged = 'Nabago na ang password.';
  static const String wrongCurrentPassword =
      'Mali ang kasalukuyang password.';

  // --- Phase-1 additions (pinned; folded into spec §11 in Phase 5) ---

  static const String logIn = 'Mag-log in';
  static const String signUp = 'Mag-sign up';
  static const String profileTitle = 'Profile';
  static const String permissionsTitle = 'Mga pahintulot';
  static const String save = 'I-save';
  static const String logOut = 'Mag-log out';
  static const String yes = 'Oo';
  static const String no = 'Hindi';
  static const String continueLabel = 'Magpatuloy';
  static const String allSet = 'Ayos na lahat. Magpatuloy.';
  static const String limitedMode =
      'Magpapatuloy nang walang ilang pahintulot. Hindi gagana ang ilang feature.';
  static const String needInternet =
      'Kailangan mo ng internet para baguhin ito.';
  static const String rateLimited =
      'Masyadong maraming pagsubok. Subukan ulit mamaya.';
  static const String nameLabel = 'Pangalan mo';
  static const String emailLabel = 'Email address';
  static const String contactNumberLabel = 'Emergency contact number';
  static const String currentPasswordLabel = 'Kasalukuyang password';
  static const String newPasswordLabel = 'Bagong password';
  static const String changePasswordLabel = 'Palitan ang password';
  static const String savedContact = 'Nai-save ang contact number.';
  static const String allow = 'Payagan';
  static const String contactInvalid =
      'Maglagay ng tamang contact number (7 hanggang 15 na numero).';
  static const String genericError = 'May problema. Subukan ulit.';
  static const String passwordLabel = 'Password';
  static const String confirmPasswordLabel = 'Kumpirmahin ang password';
  static const String confirmPasswordField =
      'Confirm password field. Nakatago ang mga karakter.';
  static const String passwordMismatch = 'Hindi tugma ang mga password.';
  static const String emailInvalid = 'Maglagay ng tamang email address.';
  static const String passwordRequired = 'Ilagay ang password mo.';
  static const String microphoneLabel = 'Mikropono';
  static const String cameraLabel = 'Camera';
  static const String phoneLabel = 'Telepono';
  static const String permissionGranted = 'Pinayagan';
  static const String permissionNotGranted = 'Hindi pa pinayagan';

  /// The one interpolation helper: `Naka-log in bilang {name}.`
  static String signedInAs(String name) => 'Naka-log in bilang $name.';
}

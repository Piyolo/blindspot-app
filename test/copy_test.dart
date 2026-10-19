import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/constants/copy.dart';

/// The complete Phase-1 copy deck, pinned verbatim in both languages.
///
/// Expected values are transcribed from the brief's tables (spec §11
/// verbatim set + Phase-1 additions + the `contactInvalid`/`genericError`
/// ruling keys) and are deliberately NOT derived from `Copy`/`CopyFil`,
/// so a corrupted deck value fails here. A *missing* key is already caught
/// by the compiler at every screen reference site; Flutter cannot
/// enumerate static members (`dart:mirrors` is unavailable), so the
/// actual values are pulled into maps explicitly below.
///
/// 46 string keys per language + the `signedInAs(name)` helper = the 47
/// pinned Phase-1 keys.
void main() {
  const Map<String, String> expectedEn = <String, String>{
    // Spec §11 (EN/FIL pairs)
    'boot': 'BlindSpot is starting.',
    'welcome':
        'Welcome to BlindSpot. You can log in, sign up, or ask a trusted person for setup help.',
    'loginField': 'Email field. Speak your email or tap to type.',
    'passwordField': 'Password field. Characters are hidden.',
    'passwordRule':
        'Password must be at least 8 characters with a letter and a number.',
    'emergencyNumberField':
        'Mobile number field. Tap to type, or speak it, starting with zero nine, or plus six three.',
    'micPermission':
        'BlindSpot needs the microphone to hear your voice commands.',
    'cameraPermission':
        'BlindSpot needs the camera to detect objects around you.',
    'phonePermission':
        'BlindSpot needs phone access to call your emergency contact.',
    'home': 'Home. Say "start detection", or choose from the menu.',
    'loginError': 'Invalid email or password.',
    'emailExists': 'This email is already registered. Try logging in.',
    'offline': 'No internet connection.',
    'serverWaking': 'The server is waking up. One moment.',
    'logoutConfirm': 'Log out? You will need to sign in again.',
    'passwordChanged': 'Password changed.',
    'wrongCurrentPassword': 'Current password is incorrect.',
    // Phase-1 additions (pinned)
    'logIn': 'Log in',
    'signUp': 'Sign up',
    'profileTitle': 'Profile',
    'permissionsTitle': 'Permissions',
    'save': 'Save',
    'logOut': 'Log out',
    'yes': 'Yes',
    'no': 'No',
    'continueLabel': 'Continue',
    'allSet': 'All set. Continue.',
    'limitedMode':
        'Continuing without some permissions. Some features will not work.',
    'needInternet': 'You need internet to change this.',
    'rateLimited': 'Too many attempts. Try again later.',
    'nameLabel': 'Your name',
    'emailLabel': 'Email address',
    'contactNumberLabel': 'Emergency contact number',
    'currentPasswordLabel': 'Current password',
    'newPasswordLabel': 'New password',
    'changePasswordLabel': 'Change password',
    'savedContact': 'Contact number saved.',
    'allow': 'Allow',
    'contactInvalid': 'Enter a valid contact number (7 to 15 digits).',
    'genericError': 'Something went wrong. Please try again.',
    // Phase-1 additions, fix round 2 (pinned)
    'passwordLabel': 'Password',
    'confirmPasswordLabel': 'Confirm password',
    'confirmPasswordField': 'Confirm password field. Characters are hidden.',
    'passwordMismatch': 'The passwords do not match.',
    'emailInvalid': 'Enter a valid email address.',
    'passwordRequired': 'Enter your password.',
  };

  const Map<String, String> expectedFil = <String, String>{
    // Spec §11 (EN/FIL pairs)
    'boot': 'Nagsisimula ang BlindSpot.',
    'welcome':
        'Maligayang pagdating sa BlindSpot. Pwede kang mag-log in, mag-sign up, o humingi ng tulong sa pinagkakatiwalaan mong tao para sa setup.',
    'loginField': 'Email field. Sabihin ang iyong email o pindutin para mag-type.',
    'passwordField': 'Password field. Nakatago ang mga karakter.',
    'passwordRule':
        'Ang password ay dapat hindi bababa sa 8 karakter, at may titik at numero.',
    'emergencyNumberField':
        'Mobile number field. Pindutin para mag-type, o sabihin, simula sa zero nine, o plus six three.',
    'micPermission':
        'Kailangan ng BlindSpot ang mikropono para marinig ang iyong mga utos.',
    'cameraPermission':
        'Kailangan ng BlindSpot ang kamera para matukoy ang mga bagay sa paligid mo.',
    'phonePermission':
        'Kailangan ng BlindSpot ang akses sa telepono para matawagan ang emergency contact mo.',
    'home': 'Home. Sabihin ang "simulan ang detection", o pumili sa menu.',
    'loginError': 'Mali ang email o password.',
    'emailExists': 'Nakarehistro na ang email na ito. Subukang mag-log in.',
    'offline': 'Walang koneksyon sa internet.',
    'serverWaking': 'Nagigising pa ang server. Sandali lang.',
    'logoutConfirm': 'Mag-log out? Kailangan mong mag-log in muli.',
    'passwordChanged': 'Nabago na ang password.',
    'wrongCurrentPassword': 'Mali ang kasalukuyang password.',
    // Phase-1 additions (pinned)
    'logIn': 'Mag-log in',
    'signUp': 'Mag-sign up',
    'profileTitle': 'Profile',
    'permissionsTitle': 'Mga pahintulot',
    'save': 'I-save',
    'logOut': 'Mag-log out',
    'yes': 'Oo',
    'no': 'Hindi',
    'continueLabel': 'Magpatuloy',
    'allSet': 'Ayos na lahat. Magpatuloy.',
    'limitedMode':
        'Magpapatuloy nang walang ilang pahintulot. Hindi gagana ang ilang feature.',
    'needInternet': 'Kailangan mo ng internet para baguhin ito.',
    'rateLimited': 'Masyadong maraming pagsubok. Subukan ulit mamaya.',
    'nameLabel': 'Pangalan mo',
    'emailLabel': 'Email address',
    'contactNumberLabel': 'Emergency contact number',
    'currentPasswordLabel': 'Kasalukuyang password',
    'newPasswordLabel': 'Bagong password',
    'changePasswordLabel': 'Palitan ang password',
    'savedContact': 'Nai-save ang contact number.',
    'allow': 'Payagan',
    'contactInvalid':
        'Maglagay ng tamang contact number (7 hanggang 15 na numero).',
    'genericError': 'May problema. Subukan ulit.',
    // Phase-1 additions, fix round 2 (pinned)
    'passwordLabel': 'Password',
    'confirmPasswordLabel': 'Kumpirmahin ang password',
    'confirmPasswordField': 'Confirm password field. Nakatago ang mga karakter.',
    'passwordMismatch': 'Hindi tugma ang mga password.',
    'emailInvalid': 'Maglagay ng tamang email address.',
    'passwordRequired': 'Ilagay ang password mo.',
  };

  // Actual values: every Copy/CopyFil string key referenced explicitly, so
  // the compiler ties this table to the deck (a key renamed away fails to
  // compile here).
  const Map<String, String> actualEn = <String, String>{
    'boot': Copy.boot,
    'welcome': Copy.welcome,
    'loginField': Copy.loginField,
    'passwordField': Copy.passwordField,
    'passwordRule': Copy.passwordRule,
    'emergencyNumberField': Copy.emergencyNumberField,
    'micPermission': Copy.micPermission,
    'cameraPermission': Copy.cameraPermission,
    'phonePermission': Copy.phonePermission,
    'home': Copy.home,
    'loginError': Copy.loginError,
    'emailExists': Copy.emailExists,
    'offline': Copy.offline,
    'serverWaking': Copy.serverWaking,
    'logoutConfirm': Copy.logoutConfirm,
    'passwordChanged': Copy.passwordChanged,
    'wrongCurrentPassword': Copy.wrongCurrentPassword,
    'logIn': Copy.logIn,
    'signUp': Copy.signUp,
    'profileTitle': Copy.profileTitle,
    'permissionsTitle': Copy.permissionsTitle,
    'save': Copy.save,
    'logOut': Copy.logOut,
    'yes': Copy.yes,
    'no': Copy.no,
    'continueLabel': Copy.continueLabel,
    'allSet': Copy.allSet,
    'limitedMode': Copy.limitedMode,
    'needInternet': Copy.needInternet,
    'rateLimited': Copy.rateLimited,
    'nameLabel': Copy.nameLabel,
    'emailLabel': Copy.emailLabel,
    'contactNumberLabel': Copy.contactNumberLabel,
    'currentPasswordLabel': Copy.currentPasswordLabel,
    'newPasswordLabel': Copy.newPasswordLabel,
    'changePasswordLabel': Copy.changePasswordLabel,
    'savedContact': Copy.savedContact,
    'allow': Copy.allow,
    'contactInvalid': Copy.contactInvalid,
    'genericError': Copy.genericError,
    'passwordLabel': Copy.passwordLabel,
    'confirmPasswordLabel': Copy.confirmPasswordLabel,
    'confirmPasswordField': Copy.confirmPasswordField,
    'passwordMismatch': Copy.passwordMismatch,
    'emailInvalid': Copy.emailInvalid,
    'passwordRequired': Copy.passwordRequired,
  };

  const Map<String, String> actualFil = <String, String>{
    'boot': CopyFil.boot,
    'welcome': CopyFil.welcome,
    'loginField': CopyFil.loginField,
    'passwordField': CopyFil.passwordField,
    'passwordRule': CopyFil.passwordRule,
    'emergencyNumberField': CopyFil.emergencyNumberField,
    'micPermission': CopyFil.micPermission,
    'cameraPermission': CopyFil.cameraPermission,
    'phonePermission': CopyFil.phonePermission,
    'home': CopyFil.home,
    'loginError': CopyFil.loginError,
    'emailExists': CopyFil.emailExists,
    'offline': CopyFil.offline,
    'serverWaking': CopyFil.serverWaking,
    'logoutConfirm': CopyFil.logoutConfirm,
    'passwordChanged': CopyFil.passwordChanged,
    'wrongCurrentPassword': CopyFil.wrongCurrentPassword,
    'logIn': CopyFil.logIn,
    'signUp': CopyFil.signUp,
    'profileTitle': CopyFil.profileTitle,
    'permissionsTitle': CopyFil.permissionsTitle,
    'save': CopyFil.save,
    'logOut': CopyFil.logOut,
    'yes': CopyFil.yes,
    'no': CopyFil.no,
    'continueLabel': CopyFil.continueLabel,
    'allSet': CopyFil.allSet,
    'limitedMode': CopyFil.limitedMode,
    'needInternet': CopyFil.needInternet,
    'rateLimited': CopyFil.rateLimited,
    'nameLabel': CopyFil.nameLabel,
    'emailLabel': CopyFil.emailLabel,
    'contactNumberLabel': CopyFil.contactNumberLabel,
    'currentPasswordLabel': CopyFil.currentPasswordLabel,
    'newPasswordLabel': CopyFil.newPasswordLabel,
    'changePasswordLabel': CopyFil.changePasswordLabel,
    'savedContact': CopyFil.savedContact,
    'allow': CopyFil.allow,
    'contactInvalid': CopyFil.contactInvalid,
    'genericError': CopyFil.genericError,
    'passwordLabel': CopyFil.passwordLabel,
    'confirmPasswordLabel': CopyFil.confirmPasswordLabel,
    'confirmPasswordField': CopyFil.confirmPasswordField,
    'passwordMismatch': CopyFil.passwordMismatch,
    'emailInvalid': CopyFil.emailInvalid,
    'passwordRequired': CopyFil.passwordRequired,
  };

  group('Phase-1 copy deck', () {
    test('the table pins all 46 string keys, in both languages', () {
      expect(expectedEn.length, 46);
      expect(expectedFil.length, 46);
      expect(expectedEn.keys.toSet(), expectedFil.keys.toSet());
      expect(actualEn.keys.toSet(), expectedEn.keys.toSet());
      expect(actualFil.keys.toSet(), expectedFil.keys.toSet());
      expect(expectedEn.values.where((v) => v.isEmpty), isEmpty);
      expect(expectedFil.values.where((v) => v.isEmpty), isEmpty);
    });

    test('Copy (EN) matches the pinned table verbatim', () {
      expect(actualEn, expectedEn);
    });

    test('CopyFil (FIL) matches the pinned table verbatim', () {
      expect(actualFil, expectedFil);
    });

    test('signedInAs helper interpolates verbatim in both languages', () {
      expect(Copy.signedInAs('Ana'), 'Signed in as Ana.');
      expect(CopyFil.signedInAs('Ana'), 'Naka-log in bilang Ana.');
    });
  });
}

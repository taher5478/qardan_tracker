import 'package:local_auth/local_auth.dart';

/// Thin wrapper over device biometrics. PIN handling lives in [AppSettings];
/// this only covers fingerprint/face.
class AuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Prompt for fingerprint/face. Returns true on success, false on cancel,
  /// lockout, or any error (the caller can then fall back to PIN).
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Qarzan Tracker',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

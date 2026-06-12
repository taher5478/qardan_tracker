import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Persistent, business-configurable settings backed by SharedPreferences.
///
/// Getters fall back to compile-time defaults when prefs aren't loaded yet, so
/// the UI (and the background isolate) never crash on early access. Call
/// [ensureLoaded] once at startup and at the top of the background sweep.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kBusiness = 'businessName';
  static const _kCurrency = 'currencySymbol';
  static const _kLock = 'lockEnabled';
  static const _kBiometric = 'biometricEnabled';
  static const _kPinHash = 'pinHash';
  static const _kRecovery = 'pinRecoveryHash';
  static const _kForeground = 'foregroundEnabled';
  static const _kDriveEnabled = 'driveBackupEnabled';
  static const _kDriveEmail = 'driveAccountEmail';
  static const _kDriveLast = 'lastDriveBackup';
  static const _kTrialStart = 'trialStartMillis';
  static const _kLicenseUntil = 'licenseValidUntilMillis';
  static const _kLicenseKey = 'activationKey';
  static const _kServerSubUntil = 'serverSubUntilMillis';
  static const _kOnboarded = 'onboardingComplete';
  static const _kLastSweep = 'lastBackgroundSweepMillis';
  static const _kSmsLink = 'smsFooterUrlEnabled';
  static const _kLastPausedNotice = 'lastPausedNoticeMillis';
  static const _kLastAlertId = 'lastSeenAlertId';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Re-read from disk to pick up values written by the background isolate
  /// (e.g. the sweep heartbeat, drive-backup time).
  Future<void> reload() async => _prefs?.reload();

  // --- Reads (safe before load) --------------------------------------------

  String get businessName =>
      _prefs?.getString(_kBusiness) ?? kDefaultBusinessName;

  String get currencySymbol =>
      _prefs?.getString(_kCurrency) ?? kCurrencySymbol;

  bool get lockEnabled => _prefs?.getBool(_kLock) ?? false;

  bool get biometricEnabled => _prefs?.getBool(_kBiometric) ?? true;

  bool get hasPin => (_prefs?.getString(_kPinHash) ?? '').isNotEmpty;

  bool get foregroundEnabled => _prefs?.getBool(_kForeground) ?? false;

  bool get onboardingComplete => _prefs?.getBool(_kOnboarded) ?? false;

  Future<void> setOnboardingComplete() async =>
      _prefs?.setBool(_kOnboarded, true);

  /// When the background sweep last actually ran — used to detect when an OEM
  /// has killed background execution.
  DateTime? get lastBackgroundSweep {
    final ms = _prefs?.getInt(_kLastSweep);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markBackgroundSweep() async =>
      _prefs?.setInt(_kLastSweep, DateTime.now().millisecondsSinceEpoch);

  /// Whether to append the app download link to reminder SMS. Default ON;
  /// only premium subscribers may turn it off.
  bool get smsFooterUrlEnabled => _prefs?.getBool(_kSmsLink) ?? true;

  Future<void> setSmsFooterUrlEnabled(bool v) async =>
      _prefs?.setBool(_kSmsLink, v);

  /// Throttle for "reminders paused" notifications (once per 24h).
  bool shouldShowPausedNotice() {
    final last = _prefs?.getInt(_kLastPausedNotice) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last >= 86400000;
  }

  Future<void> markPausedNotice() async =>
      _prefs?.setInt(_kLastPausedNotice, DateTime.now().millisecondsSinceEpoch);

  /// The last broadcast alert id the user has already seen (shown once each).
  int get lastSeenAlertId => _prefs?.getInt(_kLastAlertId) ?? -1;

  Future<void> setLastSeenAlertId(int id) async =>
      _prefs?.setInt(_kLastAlertId, id);

  bool get driveBackupEnabled => _prefs?.getBool(_kDriveEnabled) ?? false;

  String? get driveAccountEmail => _prefs?.getString(_kDriveEmail);

  DateTime? get lastDriveBackup {
    final ms = _prefs?.getInt(_kDriveLast);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // --- Writes ---------------------------------------------------------------

  Future<void> setBusinessName(String v) async =>
      _prefs?.setString(_kBusiness, v.trim());

  Future<void> setCurrencySymbol(String v) async =>
      _prefs?.setString(_kCurrency, v.trim().isEmpty ? kCurrencySymbol : v.trim());

  Future<void> setBiometricEnabled(bool v) async =>
      _prefs?.setBool(_kBiometric, v);

  Future<void> setForegroundEnabled(bool v) async =>
      _prefs?.setBool(_kForeground, v);

  Future<void> setDriveBackup(bool enabled, String? email) async {
    await _prefs?.setBool(_kDriveEnabled, enabled);
    if (email == null) {
      await _prefs?.remove(_kDriveEmail);
    } else {
      await _prefs?.setString(_kDriveEmail, email);
    }
  }

  Future<void> setLastDriveBackup(DateTime when) async =>
      _prefs?.setInt(_kDriveLast, when.millisecondsSinceEpoch);

  // --- Subscription / trial -------------------------------------------------

  /// The day the app-managed free trial began (set once, on first launch).
  DateTime? get trialStart {
    final ms = _prefs?.getInt(_kTrialStart);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Records the trial start on first launch if not already set.
  Future<void> ensureTrialStarted() async {
    if (_prefs?.getInt(_kTrialStart) == null) {
      await _prefs?.setInt(_kTrialStart, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Local cache of the activation-key expiry (from Supabase). Null = no key.
  DateTime? get licenseValidUntil {
    final ms = _prefs?.getInt(_kLicenseUntil);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String? get activationKey => _prefs?.getString(_kLicenseKey);

  Future<void> setLicense(DateTime validUntil, String key) async {
    await _prefs?.setInt(_kLicenseUntil, validUntil.millisecondsSinceEpoch);
    await _prefs?.setString(_kLicenseKey, key);
  }

  Future<void> clearLicense() async {
    await _prefs?.remove(_kLicenseUntil);
    await _prefs?.remove(_kLicenseKey);
  }

  /// Cached expiry of an active Dodo subscription (from the server).
  DateTime? get serverSubUntil {
    final ms = _prefs?.getInt(_kServerSubUntil);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setServerSub(DateTime until) async =>
      _prefs?.setInt(_kServerSubUntil, until.millisecondsSinceEpoch);

  Future<void> clearServerSub() async => _prefs?.remove(_kServerSubUntil);

  /// Enabling the lock requires a PIN to already be set.
  Future<void> setLockEnabled(bool v) async => _prefs?.setBool(_kLock, v);

  Future<void> setPin(String pin) async {
    await _prefs?.setString(_kPinHash, _hash(pin));
  }

  Future<void> clearPin() async {
    await _prefs?.remove(_kPinHash);
    await _prefs?.remove(_kRecovery);
    await _prefs?.setBool(_kLock, false);
  }

  bool verifyPin(String pin) {
    final stored = _prefs?.getString(_kPinHash) ?? '';
    return stored.isNotEmpty && stored == _hash(pin);
  }

  // --- PIN recovery code ----------------------------------------------------

  bool get hasRecovery => (_prefs?.getString(_kRecovery) ?? '').isNotEmpty;

  /// Raw recovery hash, for mirroring to the server profile.
  String? get recoveryHashRaw => _prefs?.getString(_kRecovery);

  Future<void> setRecoveryCode(String code) async =>
      _prefs?.setString(_kRecovery, _hash(_normalize(code)));

  bool verifyRecovery(String code) {
    final stored = _prefs?.getString(_kRecovery) ?? '';
    return stored.isNotEmpty && stored == _hash(_normalize(code));
  }

  String _normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // PINs are short, so a plain hash is not a strong KDF — but it keeps the PIN
  // out of plaintext storage. Real secrecy comes from the OS keystore + device
  // lock; this is a convenience gate, not vault-grade crypto.
  String _hash(String pin) =>
      sha256.convert(utf8.encode('qarzan::$pin')).toString();
}

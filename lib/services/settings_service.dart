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
  static const _kTemplate = 'smsTemplate';
  static const _kLock = 'lockEnabled';
  static const _kBiometric = 'biometricEnabled';
  static const _kPinHash = 'pinHash';
  static const _kForeground = 'foregroundEnabled';

  SharedPreferences? _prefs;

  Future<void> ensureLoaded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Reads (safe before load) --------------------------------------------

  String get businessName =>
      _prefs?.getString(_kBusiness) ?? kDefaultBusinessName;

  String get currencySymbol =>
      _prefs?.getString(_kCurrency) ?? kCurrencySymbol;

  String get smsTemplate =>
      _prefs?.getString(_kTemplate) ?? kDefaultSmsTemplate;

  bool get lockEnabled => _prefs?.getBool(_kLock) ?? false;

  bool get biometricEnabled => _prefs?.getBool(_kBiometric) ?? true;

  bool get hasPin => (_prefs?.getString(_kPinHash) ?? '').isNotEmpty;

  bool get foregroundEnabled => _prefs?.getBool(_kForeground) ?? false;

  // --- Writes ---------------------------------------------------------------

  Future<void> setBusinessName(String v) async =>
      _prefs?.setString(_kBusiness, v.trim());

  Future<void> setCurrencySymbol(String v) async =>
      _prefs?.setString(_kCurrency, v.trim().isEmpty ? kCurrencySymbol : v.trim());

  Future<void> setSmsTemplate(String v) async => _prefs?.setString(
      _kTemplate, v.trim().isEmpty ? kDefaultSmsTemplate : v.trim());

  Future<void> setBiometricEnabled(bool v) async =>
      _prefs?.setBool(_kBiometric, v);

  Future<void> setForegroundEnabled(bool v) async =>
      _prefs?.setBool(_kForeground, v);

  /// Enabling the lock requires a PIN to already be set.
  Future<void> setLockEnabled(bool v) async => _prefs?.setBool(_kLock, v);

  Future<void> setPin(String pin) async {
    await _prefs?.setString(_kPinHash, _hash(pin));
  }

  Future<void> clearPin() async {
    await _prefs?.remove(_kPinHash);
    await _prefs?.setBool(_kLock, false);
  }

  bool verifyPin(String pin) {
    final stored = _prefs?.getString(_kPinHash) ?? '';
    return stored.isNotEmpty && stored == _hash(pin);
  }

  // PINs are short, so a plain hash is not a strong KDF — but it keeps the PIN
  // out of plaintext storage. Real secrecy comes from the OS keystore + device
  // lock; this is a convenience gate, not vault-grade crypto.
  String _hash(String pin) =>
      sha256.convert(utf8.encode('qarzan::$pin')).toString();
}

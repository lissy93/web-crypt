import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_crypt/core/utils/log.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';

/// how private keys are kept between runs
enum KeyringMode {
  /// nothing decided yet
  undecided,

  /// encrypted under a master password, and persisted
  masterPassword,

  /// in memory only, gone when the app closes
  sessionOnly,
}

enum ThemeChoice { system, light, dark }

const _log = Log('storage');

/// everything that survives a restart, and nothing else
class StorageService {
  const StorageService(this._prefs, this._secure);

  /// for a platform that hands out no preferences. everything still works, it
  /// just does not survive a restart
  const StorageService.inMemory() : _prefs = null, _secure = null;

  static const _kTheme = 'theme';
  static const _kFormat = 'last.format';
  static const _kMode = 'last.mode';
  static const _kArmor = 'last.armor';
  static const _kPublicKeys = 'keys.public';
  static const _kVault = 'keys.vault';
  static const _kKeyringMode = 'keys.mode';
  static const _kMasterPassword = 'keys.master';

  final SharedPreferences? _prefs;
  final FlutterSecureStorage? _secure;

  /// falls back to an empty in-memory store when the platform hands out none
  static Future<StorageService> create() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Object catch (error) {
      _log.warn('local storage is unavailable, running without it', error);
      return const StorageService.inMemory();
    }
    // the platform keyring only exists on desktop and mobile
    const secure = kIsWeb ? null : FlutterSecureStorage();
    return StorageService(prefs, secure);
  }

  ThemeChoice get theme => ThemeChoice.values.firstWhere(
    (value) => value.name == _prefs?.getString(_kTheme),
    orElse: () => ThemeChoice.system,
  );

  Future<void> setTheme(ThemeChoice value) async =>
      _prefs?.setString(_kTheme, value.name);

  CryptoFormatKind get lastFormat => CryptoFormatKind.values.firstWhere(
    (value) => value.name == _prefs?.getString(_kFormat),
    orElse: () => CryptoFormatKind.age,
  );

  Future<void> setLastFormat(CryptoFormatKind value) async =>
      _prefs?.setString(_kFormat, value.name);

  EncryptMode get lastMode => EncryptMode.values.firstWhere(
    (value) => value.name == _prefs?.getString(_kMode),
    orElse: () => EncryptMode.passphrase,
  );

  Future<void> setLastMode(EncryptMode value) async =>
      _prefs?.setString(_kMode, value.name);

  bool get lastArmor => _prefs?.getBool(_kArmor) ?? false;

  Future<void> setLastArmor(bool value) async =>
      _prefs?.setBool(_kArmor, value);

  KeyringMode get keyringMode => KeyringMode.values.firstWhere(
    (value) => value.name == _prefs?.getString(_kKeyringMode),
    orElse: () => KeyringMode.undecided,
  );

  Future<void> setKeyringMode(KeyringMode value) async =>
      _prefs?.setString(_kKeyringMode, value.name);

  List<KeyEntry> loadPublicKeys() {
    final raw = _prefs?.getString(_kPublicKeys);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final keys = <KeyEntry>[];
      for (final item in decoded) {
        if (item is! Map<String, Object?>) continue;
        final entry = _entryOrNull(item);
        if (entry != null) keys.add(entry);
      }
      return keys;
    } on Object catch (error) {
      // a damaged list is not worth crashing over, so start clean
      _log.warn('stored public keys could not be read', error);
      return const [];
    }
  }

  KeyEntry? _entryOrNull(Map<String, Object?> json) {
    try {
      return KeyEntry.fromJson(json);
    } on Object catch (error) {
      _log.warn('one stored key could not be read, skipping it', error);
      return null;
    }
  }

  Future<void> savePublicKeys(List<KeyEntry> keys) async => _prefs?.setString(
    _kPublicKeys,
    jsonEncode([for (final key in keys) key.toJson()]),
  );

  /// the sealed private keyring, armored so it is a valid age file on its own
  String? loadSealedVault() => _prefs?.getString(_kVault);

  Future<void> saveSealedVault(String armored) async =>
      _prefs?.setString(_kVault, armored);

  Future<void> clearSealedVault() async => _prefs?.remove(_kVault);

  bool get canRememberMasterPassword => _secure != null;

  Future<String?> readRememberedMasterPassword() async {
    final secure = _secure;
    if (secure == null) return null;
    try {
      return await secure.read(key: _kMasterPassword);
    } on Object catch (error) {
      _log.warn('the system keyring could not be read', error);
      return null;
    }
  }

  Future<void> rememberMasterPassword(String? value) async {
    final secure = _secure;
    if (secure == null) return;
    try {
      if (value == null) {
        await secure.delete(key: _kMasterPassword);
      } else {
        await secure.write(key: _kMasterPassword, value: value);
      }
    } on Object catch (error) {
      // a missing platform keyring is not fatal, the password gets retyped
      _log.warn('the system keyring could not be written', error);
    }
  }

  Future<void> clearEverything() async {
    await _prefs?.remove(_kTheme);
    await _prefs?.remove(_kFormat);
    await _prefs?.remove(_kMode);
    await _prefs?.remove(_kArmor);
    await _prefs?.remove(_kPublicKeys);
    await _prefs?.remove(_kVault);
    await _prefs?.remove(_kKeyringMode);
    await rememberMasterPassword(null);
  }
}

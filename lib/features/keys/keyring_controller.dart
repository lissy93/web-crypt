import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/log.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/crypto/keyring/private_vault.dart';
import 'package:web_crypt/services/storage_service.dart';

enum VaultStatus {
  /// no private key has ever been saved, so nothing is decided
  empty,

  /// in memory only, gone when the app closes
  sessionOnly,

  /// a master password exists and the vault is open
  unlocked,

  /// a master password exists and the vault is shut
  locked,
}

class KeyringState {
  const KeyringState({
    this.keys = const [],
    this.vault = PrivateVault.empty,
    this.status = VaultStatus.empty,
    this.loading = true,
  });

  final List<KeyEntry> keys;
  final PrivateVault vault;
  final VaultStatus status;
  final bool loading;

  bool get isLocked => status == VaultStatus.locked;

  bool get hasPrivateKeys => keys.any((key) => key.hasPrivate);

  List<KeyEntry> byFormat(CryptoFormatKind format) =>
      keys.where((key) => key.format == format).toList(growable: false);

  List<KeyEntry> recipientsFor(CryptoFormatKind format) => byFormat(format);

  /// everything unlocked that could open a message. an age identity needs no
  /// passphrase, a protected PGP key is offered too and asks later
  List<Identity> get availableIdentities => [
    for (final key in keys)
      if (key.hasPrivate && vault[key.id] != null)
        Identity(
          format: key.format,
          material: vault[key.id]!,
          label: key.displayName,
        ),
  ];

  KeyringState copyWith({
    List<KeyEntry>? keys,
    PrivateVault? vault,
    VaultStatus? status,
    bool? loading,
  }) {
    return KeyringState(
      keys: keys ?? this.keys,
      vault: vault ?? this.vault,
      status: status ?? this.status,
      loading: loading ?? this.loading,
    );
  }
}

const _log = Log('keyring');

final keyringProvider = NotifierProvider<KeyringController, KeyringState>(
  KeyringController.new,
);

class KeyringController extends Notifier<KeyringState> {
  /// held only while the vault is open, so a key added later in the session
  /// can be sealed back. kept out of the state on purpose, since state gets
  /// copied, watched and dumped in debug tooling
  String? _sessionPassword;

  StorageService get _storage => ref.read(storageServiceProvider);

  CryptoService get _crypto => ref.read(cryptoServiceProvider);

  @override
  KeyringState build() {
    Future<void>.microtask(() async {
      try {
        await load();
      } on Object catch (error) {
        _log.warn('the keyring could not be loaded', error);
        state = const KeyringState(loading: false);
      }
    });
    return const KeyringState();
  }

  Future<void> load() async {
    final keys = _storage.loadPublicKeys();
    final mode = _storage.keyringMode;
    final sealed = _storage.loadSealedVault();

    var status = switch (mode) {
      KeyringMode.sessionOnly => VaultStatus.sessionOnly,
      KeyringMode.masterPassword =>
        sealed == null ? VaultStatus.empty : VaultStatus.locked,
      KeyringMode.undecided => VaultStatus.empty,
    };

    var vault = PrivateVault.empty;
    if (status == VaultStatus.locked) {
      final remembered = await _storage.readRememberedMasterPassword();
      if (remembered != null) {
        try {
          vault = await _openVault(sealed!, remembered);
          status = VaultStatus.unlocked;
          _sessionPassword = remembered;
        } on AppException catch (error) {
          // stale remembered password, so ask for it instead
          _log.warn(
            'the remembered master password no longer opens the vault',
            error,
          );
          await _storage.rememberMasterPassword(null);
        }
      }
    }

    state = KeyringState(
      keys: keys,
      vault: vault,
      status: status,
      loading: false,
    );
  }

  Future<void> unlock(String masterPassword, {bool remember = false}) async {
    final sealed = _storage.loadSealedVault();
    if (sealed == null) throw const KeyringCorrupt();
    final vault = await _openVault(sealed, masterPassword);
    if (remember) await _storage.rememberMasterPassword(masterPassword);
    _sessionPassword = masterPassword;
    state = state.copyWith(vault: vault, status: VaultStatus.unlocked);
  }

  Future<void> lock() async {
    _sessionPassword = null;
    await _storage.rememberMasterPassword(null);
    if (state.status == VaultStatus.sessionOnly) {
      state = state.copyWith(vault: PrivateVault.empty);
      return;
    }
    state = state.copyWith(
      vault: PrivateVault.empty,
      status: _storage.loadSealedVault() == null
          ? VaultStatus.empty
          : VaultStatus.locked,
    );
  }

  /// picked once, the first time a private key would be saved
  Future<void> chooseSessionOnly() async {
    _sessionPassword = null;
    await _storage.setKeyringMode(KeyringMode.sessionOnly);
    await _storage.clearSealedVault();
    await _storage.rememberMasterPassword(null);
    state = state.copyWith(status: VaultStatus.sessionOnly);
  }

  Future<void> chooseMasterPassword(
    String masterPassword, {
    bool remember = false,
  }) async {
    await _persistVault(state.vault, masterPassword);
    await _storage.setKeyringMode(KeyringMode.masterPassword);
    _sessionPassword = masterPassword;
    state = state.copyWith(status: VaultStatus.unlocked);
    if (remember) await _storage.rememberMasterPassword(masterPassword);
  }

  Future<void> changeMasterPassword(
    String current,
    String next, {
    bool remember = false,
  }) async {
    final sealed = _storage.loadSealedVault();
    if (sealed == null) throw const KeyringCorrupt();
    final vault = await _openVault(sealed, current);
    await _persistVault(vault, next);
    await _storage.rememberMasterPassword(remember ? next : null);
    _sessionPassword = next;
    state = state.copyWith(vault: vault, status: VaultStatus.unlocked);
  }

  Future<KeyEntry> generateAgeKey({String label = ''}) =>
      _generate(CryptoFormatKind.age, label: label);

  Future<KeyEntry> generatePgpKey({
    required String name,
    required String email,
    String? passphrase,
    Duration? expiry,
    String label = '',
  }) => _generate(
    CryptoFormatKind.pgp,
    label: label,
    name: name,
    email: email,
    passphrase: passphrase,
    expiry: expiry,
  );

  Future<KeyEntry> _generate(
    CryptoFormatKind format, {
    required String label,
    String name = '',
    String email = '',
    String? passphrase,
    Duration? expiry,
  }) async {
    final created = DateTime.now();
    final key = await _crypto.generateKey(
      format: format,
      name: name,
      email: email,
      passphrase: passphrase,
      expiry: expiry,
    );
    final entry = KeyEntry(
      id: _newId(),
      format: format,
      label: label,
      publicMaterial: key.publicMaterial,
      fingerprint: key.fingerprint,
      createdAt: created,
      hasPrivate: true,
      privateIsProtected: key.isProtected,
      userId: key.userId,
      expiresAt: expiry == null ? null : created.add(expiry),
    );
    await _add(entry, key.privateMaterial);
    return entry;
  }

  Future<ParsedKey> importText(String text, {String label = ''}) async {
    final parsed = await parseKeyMaterial(
      text,
      id: _newId(),
      now: DateTime.now(),
      label: label,
    );
    await _addParsed(parsed);
    return parsed;
  }

  Future<void> rename(String id, String label) async {
    final keys = [
      for (final key in state.keys)
        if (key.id == id) key.copyWith(label: label) else key,
    ];
    state = state.copyWith(keys: keys);
    await _storage.savePublicKeys(keys);
  }

  /// deleting a key with a private half needs the vault open, otherwise the
  /// entry would go but its private material would stay sealed on disk
  Future<void> delete(String id) async {
    if (state.isLocked && (byId(id)?.hasPrivate ?? false)) {
      throw const KeyringLocked();
    }
    final keys = state.keys.where((key) => key.id != id).toList();
    final vault = state.vault.without(id);
    state = state.copyWith(keys: keys, vault: vault);
    await _storage.savePublicKeys(keys);
    if (state.status == VaultStatus.unlocked) await _resealCurrent();
  }

  Future<void> clearAll() async {
    _sessionPassword = null;
    await _storage.clearEverything();
    state = const KeyringState(loading: false);
  }

  /// the private material for one key, and needs the vault open
  String? privateMaterialFor(String id) => state.vault[id];

  KeyEntry? byId(String id) {
    for (final key in state.keys) {
      if (key.id == id) return key;
    }
    return null;
  }

  Future<void> _addParsed(ParsedKey parsed) =>
      _add(parsed.entry, parsed.privateMaterial);

  Future<void> _add(KeyEntry entry, String? privateMaterial) async {
    final existing = state.keys
        .where(
          (key) =>
              key.format == entry.format &&
              key.fingerprint.toLowerCase() == entry.fingerprint.toLowerCase(),
        )
        .toList();

    // re-importing with the private half is an upgrade, not a duplicate
    if (existing.isNotEmpty) {
      final current = existing.first;
      if (privateMaterial == null || current.hasPrivate) {
        throw const DuplicateKey();
      }
      final upgraded = current.copyWith(
        hasPrivate: true,
        privateIsProtected: entry.privateIsProtected,
      );
      final keys = [
        for (final key in state.keys) key.id == current.id ? upgraded : key,
      ];
      state = state.copyWith(
        keys: keys,
        vault: state.vault.withKey(current.id, privateMaterial),
      );
      await _storage.savePublicKeys(keys);
      await _resealCurrent();
      return;
    }

    final keys = [...state.keys, entry];
    state = state.copyWith(
      keys: keys,
      vault: privateMaterial == null
          ? state.vault
          : state.vault.withKey(entry.id, privateMaterial),
    );
    await _storage.savePublicKeys(keys);
    if (privateMaterial != null) await _resealCurrent();
  }

  /// writes the vault back after it changes, only possible while it is open
  Future<void> _resealCurrent() async {
    if (state.status != VaultStatus.unlocked) return;
    final password = _sessionPassword;
    if (password == null) throw const KeyringLocked();
    await _persistVault(state.vault, password);
  }

  Future<void> _persistVault(PrivateVault vault, String masterPassword) async {
    final sealed = await _crypto.encryptBytes(
      format: CryptoFormatKind.age,
      input: vault.toBytes(),
      options: EncryptOptions.withPassphrase(masterPassword, armor: true),
    );
    await _storage.saveSealedVault(utf8.decode(sealed));
  }

  Future<PrivateVault> _openVault(String sealed, String masterPassword) async {
    final outcome = await _crypto.decryptBytes(
      input: utf8.encode(sealed),
      passphrase: masterPassword,
    );
    return PrivateVault.fromBytes(outcome.bytes);
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${state.keys.length}';
}

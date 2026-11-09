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

/// a change to the key list, and to the private vault when it is touched too
typedef _Change = ({
  List<KeyEntry> keys,
  PrivateVault Function(PrivateVault vault)? vault,
});

final keyringProvider = NotifierProvider<KeyringController, KeyringState>(
  KeyringController.new,
);

class KeyringController extends Notifier<KeyringState> {
  /// held only while the vault is open, so a key added later in the session
  /// can be sealed back. kept out of the state on purpose, since state gets
  /// copied, watched and dumped in debug tooling
  String? _sessionPassword;

  /// the sealed vault as this window last read or wrote it, which tells
  /// whether another tab or window has sealed a different one since
  String? _sealed;

  StorageService get _storage => ref.read(storageServiceProvider);

  CryptoService get _crypto => ref.read(cryptoServiceProvider);

  /// the key list as storage holds it now. the in-memory fallback keeps
  /// nothing, so there this window's copy is the only one
  List<KeyEntry> get _storedKeys =>
      _storage.persists ? _storage.loadPublicKeys() : state.keys;

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
    _sessionPassword = null;
    _sealed = null;
    final keys = _storage.loadPublicKeys();
    final sealed = _storage.loadSealedVault();
    var status = _storedStatus();

    var vault = PrivateVault.empty;
    if (status == VaultStatus.locked) {
      final remembered = await _storage.readRememberedMasterPassword();
      if (remembered != null) {
        try {
          vault = await _openVault(sealed!, remembered);
          status = VaultStatus.unlocked;
          _sessionPassword = remembered;
          _sealed = sealed;
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
    await _catchUp();
    final sealed = _storage.loadSealedVault();
    if (sealed == null) throw const KeyringCorrupt();
    final vault = await _openVault(sealed, masterPassword);
    if (remember) await _storage.rememberMasterPassword(masterPassword);
    _sessionPassword = masterPassword;
    _sealed = sealed;
    state = state.copyWith(
      keys: _storedKeys,
      vault: vault,
      status: VaultStatus.unlocked,
    );
  }

  Future<void> lock() async {
    _sessionPassword = null;
    _sealed = null;
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
    await _readyToChoose();
    _sessionPassword = null;
    await _storage.setKeyringMode(KeyringMode.sessionOnly);
    await _storage.rememberMasterPassword(null);
    state = state.copyWith(status: VaultStatus.sessionOnly);
  }

  Future<void> chooseMasterPassword(
    String masterPassword, {
    bool remember = false,
  }) async {
    await _readyToChoose();
    // the mode first, since a vault on its own already counts as chosen
    await _storage.setKeyringMode(KeyringMode.masterPassword);
    _sealed = await _persistVault(state.vault, masterPassword);
    _sessionPassword = masterPassword;
    state = state.copyWith(status: VaultStatus.unlocked);
    if (remember) await _storage.rememberMasterPassword(masterPassword);
  }

  Future<void> changeMasterPassword(
    String current,
    String next, {
    bool remember = false,
  }) async {
    await _catchUp();
    final sealed = _storage.loadSealedVault();
    if (sealed == null) throw const KeyringCorrupt();
    final vault = await _openVault(sealed, current);
    _sealed = await _persistVault(vault, next);
    await _storage.rememberMasterPassword(remember ? next : null);
    _sessionPassword = next;
    state = state.copyWith(
      keys: _storedKeys,
      vault: vault,
      status: VaultStatus.unlocked,
    );
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

  Future<void> rename(String id, String label) => _update(
    (keys) => (
      keys: [
        for (final key in keys)
          if (key.id == id) key.copyWith(label: label) else key,
      ],
      vault: null,
    ),
  );

  /// deleting a key with a private half needs the vault open, otherwise the
  /// entry would go but its private material would stay sealed on disk
  Future<void> delete(String id) => _update(
    (keys) => (
      keys: [
        for (final key in keys)
          if (key.id != id) key,
      ],
      vault: keys.any((key) => key.id == id && key.hasPrivate)
          ? (vault) => vault.without(id)
          : null,
    ),
  );

  Future<void> clearAll() async {
    try {
      await _storage.clearEverything();
    } finally {
      // whatever of it landed, this window now matches
      await _storage.reload();
      await load();
    }
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

  Future<void> _add(KeyEntry entry, String? privateMaterial) => _update((keys) {
    final existing = keys
        .where(
          (key) =>
              key.format == entry.format &&
              key.fingerprint.toLowerCase() == entry.fingerprint.toLowerCase(),
        )
        .firstOrNull;
    if (existing == null) {
      return (
        keys: [...keys, entry],
        vault: privateMaterial == null
            ? null
            : (vault) => vault.withKey(entry.id, privateMaterial),
      );
    }

    // re-importing with the private half is an upgrade, not a duplicate
    if (privateMaterial == null || existing.hasPrivate) {
      throw const DuplicateKey();
    }
    return (
      keys: [
        for (final key in keys)
          if (key.id == existing.id)
            key.copyWith(
              hasPrivate: true,
              privateIsProtected: entry.privateIsProtected,
            )
          else
            key,
      ],
      vault: (vault) => vault.withKey(existing.id, privateMaterial),
    );
  });

  /// every change goes through here, and [change] is given the list as
  /// storage holds it now rather than this window's copy, so keys another tab
  /// or window added in the meantime are kept. the vault is written before
  /// the list, so no entry claims a private half that was never sealed, and
  /// state only moves once both are written
  Future<void> _update(_Change Function(List<KeyEntry> keys) change) async {
    await _catchUp();
    final next = change(_storedKeys);
    final edit = next.vault;
    var (vault, sealed) = edit != null || state.status == VaultStatus.unlocked
        ? await _latestVault()
        : (state.vault, _sealed);
    if (edit != null) {
      vault = edit(vault);
      // session-only has no password, and keeps the vault in memory
      final password = _sessionPassword;
      if (password != null) sealed = await _persistVault(vault, password);
    }
    // memory holds the vault storage now has, whether or not the list lands,
    // and [_sealed] always names the vault memory holds
    _sealed = sealed;
    state = state.copyWith(vault: vault);
    await _storage.savePublicKeys(next.keys);
    state = state.copyWith(keys: next.keys);
  }

  /// the vault as storage holds it now and the sealed text it came from,
  /// opened again only when another tab or window has sealed a different one
  /// since this one last looked
  Future<(PrivateVault, String?)> _latestVault() async {
    if (state.status == VaultStatus.sessionOnly) return (state.vault, _sealed);
    final password = _sessionPassword;
    if (state.status != VaultStatus.unlocked || password == null) {
      throw const KeyringLocked();
    }
    final sealed = _storage.loadSealedVault();
    if (!_storage.persists || sealed == _sealed) return (state.vault, _sealed);
    if (sealed != null) {
      try {
        return (await _openVault(sealed, password), sealed);
      } on AppException {
        // sealed under a different master password since
      }
    }
    await load();
    throw const KeyringChanged();
  }

  /// what storage says about the private keys, before anything is unlocked.
  /// a sealed vault is the one that counts, whatever the mode says
  VaultStatus _storedStatus() {
    if (_storage.loadSealedVault() != null) return VaultStatus.locked;
    return _storage.keyringMode == KeyringMode.sessionOnly
        ? VaultStatus.sessionOnly
        : VaultStatus.empty;
  }

  /// the mode is chosen once, from an empty keyring, and never over one that
  /// another tab or window has already chosen
  Future<void> _readyToChoose() async {
    await _catchUp();
    if (state.status != VaultStatus.empty) throw const KeyringChanged();
  }

  /// reads storage again before a change. if another tab or window has since
  /// chosen a mode, sealed a vault or cleared everything, this one takes that
  /// on rather than writing over it
  Future<void> _catchUp() async {
    if (!_storage.persists) return;
    await _storage.reload();
    final believed = state.status == VaultStatus.unlocked
        ? VaultStatus.locked
        : state.status;
    if (_storedStatus() == believed) return;
    await load();
    throw const KeyringChanged();
  }

  Future<String> _persistVault(
    PrivateVault vault,
    String masterPassword,
  ) async {
    final sealed = await _crypto.encryptBytes(
      format: CryptoFormatKind.age,
      input: vault.toBytes(),
      options: EncryptOptions.withPassphrase(masterPassword, armor: true),
    );
    final armored = utf8.decode(sealed);
    await _storage.saveSealedVault(armored);
    return armored;
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

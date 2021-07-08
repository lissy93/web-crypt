import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/services/storage_service.dart';

import '../support/harness.dart';

/// the keyring is the one place where getting it wrong loses somebody's keys,
/// so these drive the controller directly against real storage
void main() {
  Future<(ProviderContainer, StorageService)> boot([
    StorageService? existing,
  ]) async {
    final storage = existing ?? await testStorage();
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    // the controller loads on the first read
    container.read(keyringProvider);
    await Future<void>.delayed(Duration.zero);
    return (container, storage);
  }

  test('a fresh keyring has decided nothing', () async {
    final (container, _) = await boot();
    final state = container.read(keyringProvider);
    expect(state.status, VaultStatus.empty);
    expect(state.keys, isEmpty);
    expect(state.loading, isFalse);
  });

  test('session only keeps keys in memory and writes nothing', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);

    await keyring.chooseSessionOnly();
    await keyring.generateAgeKey(label: 'ephemeral');

    expect(container.read(keyringProvider).keys, hasLength(1));
    expect(container.read(keyringProvider).availableIdentities, hasLength(1));
    // the public half is still remembered, the private half is not
    expect(storage.loadPublicKeys(), hasLength(1));
    expect(storage.loadSealedVault(), isNull);
  });

  test('a key added after unlocking still reaches disk', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);

    // set up with a master password, without asking to remember it
    await keyring.chooseMasterPassword('master password');
    await keyring.generateAgeKey(label: 'first');
    final afterFirst = storage.loadSealedVault();
    expect(afterFirst, isNotNull);

    // a key added after unlocking has to be sealed too, not just held
    await keyring.generateAgeKey(label: 'second');
    expect(storage.loadSealedVault(), isNot(afterFirst));

    final (restarted, _) = await boot(storage);
    final reloaded = restarted.read(keyringProvider);
    expect(reloaded.keys, hasLength(2));
    expect(reloaded.status, VaultStatus.locked);
    expect(reloaded.availableIdentities, isEmpty);

    await restarted.read(keyringProvider.notifier).unlock('master password');
    expect(
      restarted.read(keyringProvider).availableIdentities,
      hasLength(2),
      reason: 'both private keys should come back',
    );
  });

  test('the wrong master password does not unlock', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('right');
    await keyring.generateAgeKey();

    final (restarted, _) = await boot(storage);
    await expectLater(
      restarted.read(keyringProvider.notifier).unlock('wrong'),
      throwsA(isA<WrongPassphrase>()),
    );
    expect(restarted.read(keyringProvider).status, VaultStatus.locked);
  });

  test('locking forgets the private keys but keeps the public ones', () async {
    final (container, _) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('master');
    await keyring.generateAgeKey(label: 'mine');

    await keyring.lock();
    final locked = container.read(keyringProvider);
    expect(locked.status, VaultStatus.locked);
    expect(locked.availableIdentities, isEmpty);
    expect(locked.keys, hasLength(1));
  });

  test('changing the master password re-seals under the new one', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('old one');
    await keyring.generateAgeKey();

    await keyring.changeMasterPassword('old one', 'new one');

    final (restarted, _) = await boot(storage);
    await expectLater(
      restarted.read(keyringProvider.notifier).unlock('old one'),
      throwsA(isA<WrongPassphrase>()),
    );
    await restarted.read(keyringProvider.notifier).unlock('new one');
    expect(restarted.read(keyringProvider).availableIdentities, hasLength(1));
  });

  test(
    'the same key twice is refused, but its private half upgrades it',
    () async {
      final (container, _) = await boot();
      final keyring = container.read(keyringProvider.notifier);
      await keyring.chooseSessionOnly();

      final generated = await keyring.generateAgeKey(label: 'mine');
      final recipient = generated.publicMaterial;

      await expectLater(
        keyring.importText(recipient),
        throwsA(isA<DuplicateKey>()),
      );
      expect(container.read(keyringProvider).keys, hasLength(1));
    },
  );

  test('a public key gains its private half on re-import', () async {
    final (container, _) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseSessionOnly();

    // make a keypair elsewhere, import only the public half first
    final other = await keyring.generateAgeKey(label: 'temp');
    final identity = keyring.privateMaterialFor(other.id)!;
    final recipient = other.publicMaterial;
    await keyring.delete(other.id);

    await keyring.importText(recipient, label: 'theirs');
    expect(container.read(keyringProvider).keys.single.hasPrivate, isFalse);

    await keyring.importText(identity);
    final upgraded = container.read(keyringProvider).keys.single;
    expect(upgraded.hasPrivate, isTrue);
    expect(upgraded.label, 'theirs', reason: 'the label should survive');
    expect(container.read(keyringProvider).keys, hasLength(1));
  });

  test('deleting removes the private half too', () async {
    final (container, _) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseSessionOnly();
    final entry = await keyring.generateAgeKey();

    await keyring.delete(entry.id);
    expect(container.read(keyringProvider).keys, isEmpty);
    expect(keyring.privateMaterialFor(entry.id), isNull);
  });

  test('a private key cannot be deleted while the vault is locked', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('master');
    final entry = await keyring.generateAgeKey();
    final sealed = storage.loadSealedVault();
    await keyring.lock();

    // deleting the entry has to reach the sealed private material too
    await expectLater(keyring.delete(entry.id), throwsA(isA<KeyringLocked>()));
    expect(container.read(keyringProvider).keys, hasLength(1));
    expect(storage.loadSealedVault(), sealed);

    await keyring.unlock('master');
    await keyring.delete(entry.id);
    expect(container.read(keyringProvider).keys, isEmpty);
    expect(storage.loadSealedVault(), isNot(sealed));
  });

  test('a public key can still be deleted while the vault is locked', () async {
    final (container, _) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('master');
    await keyring.generateAgeKey();
    final theirs = await keyring.importText(
      (await generateAgeKeyPair()).recipient,
    );
    await keyring.lock();

    await keyring.delete(theirs.entry.id);
    expect(container.read(keyringProvider).keys, hasLength(1));
  });

  test('clearing everything empties storage as well as memory', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseMasterPassword('master');
    await keyring.generateAgeKey();

    await keyring.clearAll();
    expect(container.read(keyringProvider).keys, isEmpty);
    expect(storage.loadPublicKeys(), isEmpty);
    expect(storage.loadSealedVault(), isNull);
    expect(storage.keyringMode, KeyringMode.undecided);
  });
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
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
    expect(storage.loadPublicKeys().single.hasPrivate, isFalse);
    expect(storage.loadSealedVault(), isNull);
  });

  test('a session-only key is private only in the window holding it', () async {
    final (a, storage) = await boot();
    await a.read(keyringProvider.notifier).chooseSessionOnly();
    final (b, _) = await boot(storage);

    await a.read(keyringProvider.notifier).generateAgeKey(label: 'in a');
    await b
        .read(keyringProvider.notifier)
        .importText((await generateAgeKeyPair()).recipient, label: 'friend');

    final inB = {
      for (final key in b.read(keyringProvider).keys) key.label: key,
    };
    expect(inB['in a']!.hasPrivate, isFalse);
    expect(a.read(keyringProvider).keys.single.hasPrivate, isTrue);
  });

  test('after a restart a session-only key can be imported again', () async {
    final (container, storage) = await boot();
    final keyring = container.read(keyringProvider.notifier);
    await keyring.chooseSessionOnly();
    final entry = await keyring.generateAgeKey(label: 'mine');
    final identity = keyring.privateMaterialFor(entry.id)!;

    final (restarted, _) = await boot(storage);
    final again = restarted.read(keyringProvider.notifier);
    expect(restarted.read(keyringProvider).keys.single.hasPrivate, isFalse);

    await again.importText(identity);
    final key = restarted.read(keyringProvider).keys.single;
    expect(key.hasPrivate, isTrue);
    expect(key.label, 'mine');
    expect(restarted.read(keyringProvider).availableIdentities, hasLength(1));
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

  test('the in-memory fallback still holds keys for the session', () async {
    for (final choose in [
      (KeyringController keyring) => keyring.chooseSessionOnly(),
      (KeyringController keyring) => keyring.chooseMasterPassword('master'),
    ]) {
      final (container, _) = await boot(const StorageService.inMemory());
      final keyring = container.read(keyringProvider.notifier);
      await choose(keyring);
      await keyring.generateAgeKey();
      await keyring.generateAgeKey();
      expect(container.read(keyringProvider).availableIdentities, hasLength(2));
    }
  });

  test('a sealed vault counts even if its mode was never written', () async {
    final (container, storage) = await boot();
    await container
        .read(keyringProvider.notifier)
        .chooseMasterPassword('master');
    await container.read(keyringProvider.notifier).generateAgeKey();

    final (restarted, _) = await boot(
      await testStorage({
        'keys.vault': storage.loadSealedVault()!,
        'keys.public': jsonEncode([
          for (final key in storage.loadPublicKeys()) key.toJson(),
        ]),
      }),
    );
    expect(restarted.read(keyringProvider).status, VaultStatus.locked);
  });

  group('a write that does not land', () {
    Future<(ProviderContainer, StorageService, RefusingPrefs)> booted() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = RefusingPrefs(await SharedPreferences.getInstance());
      final (container, storage) = await boot(StorageService(prefs, null));
      return (container, storage, prefs);
    }

    test('a refused mode leaves nothing half chosen', () async {
      final (container, _, prefs) = await booted();
      final keyring = container.read(keyringProvider.notifier);

      prefs.refused.add('keys.mode');
      await expectLater(
        keyring.chooseMasterPassword('master'),
        throwsA(isA<StorageFailed>()),
      );
      expect(container.read(keyringProvider).status, VaultStatus.empty);

      prefs.refused.clear();
      await keyring.chooseMasterPassword('master');
      expect(container.read(keyringProvider).status, VaultStatus.unlocked);
    });

    test('a refused vault adds nothing', () async {
      final (container, storage, prefs) = await booted();
      final keyring = container.read(keyringProvider.notifier);
      await keyring.chooseMasterPassword('master');

      prefs.refused.add('keys.vault');
      await expectLater(
        keyring.generateAgeKey(),
        throwsA(isA<StorageFailed>()),
      );
      expect(container.read(keyringProvider).keys, isEmpty);
      expect(storage.loadPublicKeys(), isEmpty);
    });

    test('a refused list leaves this window as it was', () async {
      final (container, storage, prefs) = await booted();
      final keyring = container.read(keyringProvider.notifier);
      await keyring.chooseMasterPassword('master');

      prefs.refused.add('keys.public');
      await expectLater(
        keyring.generateAgeKey(),
        throwsA(isA<StorageFailed>()),
      );
      expect(container.read(keyringProvider).keys, isEmpty);

      prefs.refused.clear();
      await keyring.generateAgeKey();
      final (fresh, _) = await boot(storage);
      await fresh.read(keyringProvider.notifier).unlock('master');
      expect(fresh.read(keyringProvider).availableIdentities, hasLength(1));
    });

    test(
      'a delete whose list is refused still drops the private half',
      () async {
        final (container, storage, prefs) = await booted();
        final keyring = container.read(keyringProvider.notifier);
        await keyring.chooseMasterPassword('master');
        final entry = await keyring.generateAgeKey();

        // the vault was already saved without it, so memory should agree
        prefs.refused.add('keys.public');
        await expectLater(
          keyring.delete(entry.id),
          throwsA(isA<StorageFailed>()),
        );
        expect(keyring.privateMaterialFor(entry.id), isNull);
        expect(container.read(keyringProvider).availableIdentities, isEmpty);

        prefs.refused.clear();
        await keyring.delete(entry.id);
        expect(storage.loadPublicKeys(), isEmpty);
      },
    );

    test('a refused delete keeps the key and its private half', () async {
      final (container, storage, prefs) = await booted();
      final keyring = container.read(keyringProvider.notifier);
      await keyring.chooseMasterPassword('master');
      final entry = await keyring.generateAgeKey();

      prefs.refused.add('keys.vault');
      await expectLater(
        keyring.delete(entry.id),
        throwsA(isA<StorageFailed>()),
      );
      expect(container.read(keyringProvider).keys, hasLength(1));
      expect(keyring.privateMaterialFor(entry.id), isNotNull);
      expect(storage.loadPublicKeys(), hasLength(1));
    });

    test('a clear that is refused keeps the keys reachable', () async {
      final (container, storage, prefs) = await booted();
      final keyring = container.read(keyringProvider.notifier);
      await keyring.chooseMasterPassword('master');
      await keyring.generateAgeKey();

      prefs.refused.add('keys.vault');
      await expectLater(keyring.clearAll(), throwsA(isA<StorageFailed>()));
      expect(storage.loadPublicKeys(), hasLength(1));
      expect(container.read(keyringProvider).keys, hasLength(1));
      expect(container.read(keyringProvider).status, VaultStatus.locked);

      prefs.refused.clear();
      await keyring.clearAll();
      expect(storage.loadSealedVault(), isNull);
      expect(container.read(keyringProvider).keys, isEmpty);
    });
  });

  // each container is a separate window, all sharing the same storage
  group('two windows on one keyring', () {
    Future<ProviderContainer> unlocked(StorageService storage) async {
      final (container, _) = await boot(storage);
      await container.read(keyringProvider.notifier).unlock('master');
      return container;
    }

    test('keys added in each are all kept', () async {
      final (a, storage) = await boot();
      await a.read(keyringProvider.notifier).chooseMasterPassword('master');
      final b = await unlocked(storage);

      await a.read(keyringProvider.notifier).generateAgeKey(label: 'from a');
      await b.read(keyringProvider.notifier).generateAgeKey(label: 'from b');
      await a
          .read(keyringProvider.notifier)
          .importText((await generateAgeKeyPair()).recipient, label: 'friend');

      final fresh = await unlocked(storage);
      final keyring = fresh.read(keyringProvider);
      expect(
        keyring.keys.map((key) => key.label),
        unorderedEquals(['from a', 'from b', 'friend']),
      );
      expect(keyring.availableIdentities, hasLength(2));
      expect(
        a.read(keyringProvider).availableIdentities,
        hasLength(2),
        reason: 'even a public import picks up what the other window sealed',
      );
    });

    test('a change sees writes that landed behind its cached copy', () async {
      final (a, storage) = await boot();
      final keyring = a.read(keyringProvider.notifier);
      await keyring.chooseMasterPassword('master');
      final mine = await keyring.generateAgeKey(label: 'mine');

      // another tab's import reaches the store, but not this tab's cache
      final friend = await parseKeyMaterial(
        (await generateAgeKeyPair()).recipient,
        id: 'friend',
        now: DateTime.now(),
        label: 'friend',
      );
      SharedPreferences.setMockInitialValues({
        'keys.mode': storage.keyringMode.name,
        'keys.vault': storage.loadSealedVault()!,
        'keys.public': jsonEncode([
          for (final key in [...storage.loadPublicKeys(), friend.entry])
            key.toJson(),
        ]),
      });
      expect(storage.loadPublicKeys(), hasLength(1));

      await keyring.rename(mine.id, 'still mine');
      expect(
        storage.loadPublicKeys().map((key) => key.label),
        unorderedEquals(['still mine', 'friend']),
      );
    });

    test('a refused write does not lose a key sealed elsewhere', () async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final refusing = RefusingPrefs(shared);
      final (a, storage) = await boot(StorageService(shared, null));
      await a.read(keyringProvider.notifier).chooseMasterPassword('master');
      final (b, _) = await boot(StorageService(refusing, null));
      await b.read(keyringProvider.notifier).unlock('master');

      await a.read(keyringProvider.notifier).generateAgeKey(label: 'from a');
      refusing.refused.add('keys.public');
      await expectLater(
        b.read(keyringProvider.notifier).generateAgeKey(label: 'refused'),
        throwsA(isA<StorageFailed>()),
      );
      refusing.refused.clear();
      await b.read(keyringProvider.notifier).generateAgeKey(label: 'from b');

      final fresh = await unlocked(storage);
      expect(
        fresh.read(keyringProvider).keys.map((key) => key.label),
        unorderedEquals(['from a', 'from b']),
      );
      expect(fresh.read(keyringProvider).availableIdentities, hasLength(2));
    });

    test('a vault resealed under a new password is not overwritten', () async {
      final (a, storage) = await boot();
      await a.read(keyringProvider.notifier).chooseMasterPassword('master');
      final b = await unlocked(storage);
      await a.read(keyringProvider.notifier).generateAgeKey(label: 'kept');
      await a
          .read(keyringProvider.notifier)
          .changeMasterPassword('master', 'changed');

      await expectLater(
        b.read(keyringProvider.notifier).generateAgeKey(label: 'lost'),
        throwsA(isA<KeyringChanged>()),
      );
      expect(b.read(keyringProvider).status, VaultStatus.locked);

      final (fresh, _) = await boot(storage);
      await fresh.read(keyringProvider.notifier).unlock('changed');
      expect(fresh.read(keyringProvider).keys.single.label, 'kept');
      expect(fresh.read(keyringProvider).availableIdentities, hasLength(1));
    });

    test('a window catches up when another clears everything', () async {
      final (a, storage) = await boot();
      await a.read(keyringProvider.notifier).chooseMasterPassword('master');
      await a.read(keyringProvider.notifier).generateAgeKey();
      final (b, _) = await boot(storage);
      expect(b.read(keyringProvider).status, VaultStatus.locked);

      await a.read(keyringProvider.notifier).clearAll();
      final recipient = (await generateAgeKeyPair()).recipient;
      await expectLater(
        b.read(keyringProvider.notifier).importText(recipient),
        throwsA(isA<KeyringChanged>()),
      );
      expect(b.read(keyringProvider).status, VaultStatus.empty);

      await b.read(keyringProvider.notifier).importText(recipient);
      expect(storage.loadPublicKeys(), hasLength(1));
    });

    test('a mode chosen in another window is not chosen over', () async {
      final (a, storage) = await boot();
      final (b, _) = await boot(storage);
      await a.read(keyringProvider.notifier).chooseMasterPassword('master');
      await a.read(keyringProvider.notifier).generateAgeKey();
      final sealed = storage.loadSealedVault();

      for (final choose in [
        () => b.read(keyringProvider.notifier).chooseSessionOnly(),
        () => b.read(keyringProvider.notifier).chooseMasterPassword('other'),
      ]) {
        await expectLater(choose(), throwsA(isA<KeyringChanged>()));
      }
      expect(storage.loadSealedVault(), sealed);
      expect(storage.keyringMode, KeyringMode.masterPassword);
      expect(b.read(keyringProvider).status, VaultStatus.locked);
    });
  });
}

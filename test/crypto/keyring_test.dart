import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/crypto/keyring/private_vault.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';

Future<Uint8List> seal(PrivateVault vault, String password) => collectBytes(
  const AgeFormat().encrypt(
    Stream.value(vault.toBytes()),
    EncryptOptions.withPassphrase(password, armor: true),
  ),
);

Future<PrivateVault> open(Uint8List sealed, String password) async {
  final plaintext = await collectBytes(
    const AgeFormat().decrypt(
      Stream.value(sealed),
      DecryptOptions(passphrase: password),
    ),
  );
  return PrivateVault.fromBytes(plaintext);
}

void main() {
  group('PrivateVault', () {
    test('seals and opens under a master password', () async {
      const vault = PrivateVault({'a': 'AGE-SECRET-KEY-1AAA', 'b': 'armored'});
      final sealed = await seal(vault, 'master');
      final opened = await open(sealed, 'master');
      expect(opened.materials, vault.materials);
    });

    test('the sealed form is a standard armored age file', () async {
      final sealed = await seal(const PrivateVault({'a': 'x'}), 'master');
      expect(
        utf8.decode(sealed),
        startsWith('-----BEGIN AGE ENCRYPTED FILE-----'),
      );
      expect(
        utf8.decode(sealed).trimRight(),
        endsWith('-----END AGE ENCRYPTED FILE-----'),
      );
    });

    test('the wrong master password does not open it', () async {
      final sealed = await seal(const PrivateVault({'a': 'x'}), 'master');
      await expectLater(
        open(sealed, 'not master'),
        throwsA(isA<WrongPassphrase>()),
      );
    });

    test('an empty vault round trips', () async {
      final sealed = await seal(PrivateVault.empty, 'master');
      final opened = await open(sealed, 'master');
      expect(opened.isEmpty, isTrue);
    });

    test('adding and removing keys does not mutate the original', () {
      const vault = PrivateVault({'a': '1'});
      final bigger = vault.withKey('b', '2');
      expect(vault.materials.keys, ['a']);
      expect(bigger.materials.keys, ['a', 'b']);
      expect(bigger.without('a').materials.keys, ['b']);
      expect(bigger['b'], '2');
      expect(bigger['missing'], isNull);
    });

    test('the stored JSON carries a version so it can be migrated', () {
      final json =
          jsonDecode(utf8.decode(const PrivateVault({'a': '1'}).toBytes()))
              as Map<String, Object?>;
      expect(json['version'], 1);
      expect(json['keys'], {'a': '1'});
    });

    test('a future version is refused rather than misread', () {
      final future = utf8.encode(
        jsonEncode({'version': 99, 'keys': <String, String>{}}),
      );
      expect(
        () => PrivateVault.fromBytes(future),
        throwsA(isA<KeyringCorrupt>()),
      );
    });

    test('damaged contents are refused', () {
      expect(
        () => PrivateVault.fromBytes(utf8.encode('not json')),
        throwsA(isA<KeyringCorrupt>()),
      );
      expect(
        () => PrivateVault.fromBytes(utf8.encode('[]')),
        throwsA(isA<KeyringCorrupt>()),
      );
      expect(
        () => PrivateVault.fromBytes(utf8.encode('{"version":1}')),
        throwsA(isA<KeyringCorrupt>()),
      );
      expect(
        () => PrivateVault.fromBytes(const [0xff, 0xfe]),
        throwsA(isA<KeyringCorrupt>()),
      );
    });

    test('unexpected value types are dropped, not crashed on', () {
      final mixed = utf8.encode(
        jsonEncode({
          'version': 1,
          'keys': {'good': 'value', 'bad': 42},
        }),
      );
      final vault = PrivateVault.fromBytes(mixed);
      expect(vault.materials, {'good': 'value'});
    });
  });

  group('KeyEntry', () {
    final entry = KeyEntry(
      id: 'abc',
      format: CryptoFormatKind.pgp,
      label: 'Work',
      publicMaterial: 'armored',
      fingerprint: 'AABBCCDD',
      createdAt: DateTime.utc(2024, 3, 4),
      hasPrivate: true,
      userId: 'Someone <s@example.com>',
    );

    test('survives a JSON round trip', () {
      final restored = KeyEntry.fromJson(entry.toJson());
      expect(restored.id, entry.id);
      expect(restored.format, entry.format);
      expect(restored.label, entry.label);
      expect(restored.fingerprint, entry.fingerprint);
      expect(restored.createdAt.toUtc(), entry.createdAt.toUtc());
      expect(restored.hasPrivate, isTrue);
      expect(restored.userId, entry.userId);
      expect(restored.expiresAt, isNull);
    });

    test('display name falls back through label, user id, fingerprint', () {
      expect(entry.displayName, 'Work');
      expect(entry.copyWith(label: '').displayName, 'Someone <s@example.com>');
      final bare = KeyEntry(
        id: 'x',
        format: CryptoFormatKind.age,
        label: '',
        publicMaterial: 'age1abc',
        fingerprint: 'age1abc',
        createdAt: DateTime.utc(2024),
      );
      expect(bare.displayName, 'age1abc');
    });

    test('expiry is respected', () {
      final expired = KeyEntry(
        id: 'x',
        format: CryptoFormatKind.pgp,
        label: '',
        publicMaterial: '',
        fingerprint: '',
        createdAt: DateTime.utc(2020),
        expiresAt: DateTime.utc(2021),
      );
      expect(expired.isExpired, isTrue);
      expect(entry.isExpired, isFalse);
    });
  });

  group('key import', () {
    test('an age recipient', () async {
      final pair = await generateAgeKeyPair();
      final parsed = await parseKeyMaterial(
        pair.recipient,
        id: 'a',
        now: DateTime.utc(2024),
      );
      expect(parsed.entry.format, CryptoFormatKind.age);
      expect(parsed.isPrivate, isFalse);
      expect(parsed.entry.publicMaterial, pair.recipient);
    });

    test('an age identity, including a real identity file', () async {
      final pair = await generateAgeKeyPair();
      for (final material in [
        pair.identity,
        ageIdentityFile(pair.identity, pair.recipient, DateTime.utc(2024)),
      ]) {
        final parsed = await parseKeyMaterial(
          material,
          id: 'a',
          now: DateTime.utc(2024),
        );
        expect(parsed.isPrivate, isTrue);
        expect(parsed.privateMaterial, pair.identity);
        expect(parsed.entry.publicMaterial, pair.recipient);
        expect(parsed.entry.hasPrivate, isTrue);
      }
    });

    test('a PGP public key', () async {
      final pair = generatePgpKeyPair(name: 'Pub', email: 'pub@example.com');
      final parsed = await parseKeyMaterial(
        pair.publicKey,
        id: 'a',
        now: DateTime.utc(2024),
      );
      expect(parsed.entry.format, CryptoFormatKind.pgp);
      expect(parsed.isPrivate, isFalse);
      expect(parsed.entry.fingerprint, pair.fingerprint);
      expect(parsed.entry.userId, 'Pub <pub@example.com>');
    });

    test('a PGP private key, protected or not', () async {
      final open = generatePgpKeyPair(name: 'Open');
      final shut = generatePgpKeyPair(name: 'Shut', passphrase: 'pw');
      final openParsed = await parseKeyMaterial(
        open.privateKey,
        id: 'a',
        now: DateTime.utc(2024),
      );
      final shutParsed = await parseKeyMaterial(
        shut.privateKey,
        id: 'b',
        now: DateTime.utc(2024),
      );
      expect(openParsed.isPrivate, isTrue);
      expect(openParsed.entry.privateIsProtected, isFalse);
      expect(shutParsed.entry.privateIsProtected, isTrue);
      // the public half is always stored, even for a protected key
      expect(shutParsed.entry.publicMaterial, isNotEmpty);
    });

    test('rubbish is refused', () async {
      for (final material in ['', 'hello', 'age1', '-----BEGIN NOTHING-----']) {
        await expectLater(
          parseKeyMaterial(material, id: 'a', now: DateTime.utc(2024)),
          throwsA(isA<InvalidKeyMaterial>()),
          reason: 'accepted "$material"',
        );
      }
    });
  });
}

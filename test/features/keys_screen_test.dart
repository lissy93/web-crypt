import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';
import 'package:web_crypt/features/keys/keys_screen.dart';
import 'package:web_crypt/services/storage_service.dart';

import '../support/harness.dart';

Map<String, Object> seedWithKeys(List<KeyEntry> keys) => {
  'flutter.keys.public': jsonEncode([for (final k in keys) k.toJson()]),
};

void main() {
  late String ageRecipient;
  late String pgpPublicKey;
  late String pgpFingerprint;

  setUpAll(() async {
    ageRecipient = (await generateAgeKeyPair()).recipient;
    final pgp = generatePgpKeyPair(name: 'Alice', email: 'alice@example.com');
    pgpPublicKey = pgp.publicKey;
    pgpFingerprint = pgp.fingerprint;
  });

  testWidgets('empty state explains what keys are for', (tester) async {
    await tester.pumpScreen(const KeysScreen());

    expect(find.text('No keys yet'), findsOneWidget);
    expect(
      find.textContaining('age keys are short and simple'),
      findsOneWidget,
    );
    expect(
      find.textContaining('PGP keys are the older standard'),
      findsOneWidget,
    );
    expect(find.text('New key'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('lists stored keys grouped by format', (tester) async {
    final storage = await testStorage(
      seedWithKeys([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.age,
          label: 'My age key',
          publicMaterial: ageRecipient,
          fingerprint: ageRecipient,
          createdAt: DateTime.utc(2024, 5, 1),
        ),
        KeyEntry(
          id: '2',
          format: CryptoFormatKind.pgp,
          label: 'Work PGP',
          publicMaterial: pgpPublicKey,
          fingerprint: pgpFingerprint,
          createdAt: DateTime.utc(2024, 6, 2),
          userId: 'Alice <alice@example.com>',
        ),
      ]),
    );
    await tester.pumpScreen(const KeysScreen(), storage: storage);

    expect(find.text('No keys yet'), findsNothing);
    expect(find.text('age'), findsOneWidget);
    expect(find.text('PGP'), findsOneWidget);
    expect(find.text('My age key'), findsOneWidget);
    expect(find.text('Work PGP'), findsOneWidget);
    expect(find.text('2024-05-01'), findsOneWidget);
  });

  testWidgets('a key with a private half is marked', (tester) async {
    final storage = await testStorage(
      seedWithKeys([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.age,
          label: 'Mine',
          publicMaterial: ageRecipient,
          fingerprint: ageRecipient,
          createdAt: DateTime.utc(2024),
          hasPrivate: true,
        ),
      ]),
    );
    await tester.pumpScreen(const KeysScreen(), storage: storage);

    expect(find.text('private'), findsOneWidget);
  });

  testWidgets('an expired key is called out', (tester) async {
    final storage = await testStorage(
      seedWithKeys([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.pgp,
          label: 'Old',
          publicMaterial: pgpPublicKey,
          fingerprint: pgpFingerprint,
          createdAt: DateTime.utc(2020),
          expiresAt: DateTime.utc(2021),
        ),
      ]),
    );
    await tester.pumpScreen(const KeysScreen(), storage: storage);

    expect(find.text('expired'), findsOneWidget);
  });

  testWidgets('a locked keyring offers to unlock', (tester) async {
    final storage = await testStorage({
      'flutter.keys.mode': KeyringMode.masterPassword.name,
      'flutter.keys.vault':
          '-----BEGIN AGE ENCRYPTED FILE-----\nZm9v\n'
          '-----END AGE ENCRYPTED FILE-----',
    });
    await tester.pumpScreen(const KeysScreen(), storage: storage);

    expect(find.text('Your keyring is locked.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('the new key sheet offers both formats', (tester) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();

    expect(find.text('New key'), findsWidgets);
    expect(find.text('Create key'), findsOneWidget);
    expect(find.textContaining('A short X25519 keypair'), findsOneWidget);

    await tester.tap(find.text('PGP').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('An Ed25519 key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
  });

  testWidgets('a PGP key needs a name or an email', (tester) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PGP').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();

    expect(find.text('PGP keys need a name or an email.'), findsOneWidget);
  });

  testWidgets('generating an age key asks where private keys should live', (
    tester,
  ) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();

    expect(find.text('Where should this private key live?'), findsOneWidget);
    expect(
      find.textContaining('locked with a master password'),
      findsOneWidget,
    );
    expect(find.text('This session only'), findsOneWidget);
    expect(
      find.text('There is no way to recover this password.'),
      findsOneWidget,
    );
  });

  testWidgets('session only mode creates the key without a password', (
    tester,
  ) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('This session only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpUntil(find.text('Recipient'));

    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Export public'), findsOneWidget);
    expect(find.text('Reveal private'), findsOneWidget);
  });

  testWidgets('the import sheet takes a pasted key', (tester) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Import a key'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Or paste it here'),
      ageRecipient,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Import').last);
    await tester.pumpUntil(find.text('Recipient'));

    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Reveal private'), findsNothing);
  });

  testWidgets('importing rubbish says so', (tester) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Or paste it here'),
      'this is not a key',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Import').last);
    await tester.pumpUntil(find.text('That is not a key we recognise.'));

    expect(find.text('That is not a key we recognise.'), findsOneWidget);
  });

  testWidgets('deleting asks first and names the key', (tester) async {
    final storage = await testStorage(
      seedWithKeys([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.age,
          label: 'Doomed',
          publicMaterial: ageRecipient,
          fingerprint: ageRecipient,
          createdAt: DateTime.utc(2024),
        ),
      ]),
    );
    await tester.pumpScreen(const KeysScreen(), storage: storage);

    await tester.tap(find.text('Doomed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete "Doomed"?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.loadPublicKeys(), hasLength(1));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(storage.loadPublicKeys(), isEmpty);
    expect(find.text('No keys yet'), findsOneWidget);
  });

  testWidgets('revealing a private key warns first', (tester) async {
    await tester.pumpScreen(const KeysScreen());
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This session only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpUntil(find.text('Reveal private'));

    await tester.ensureVisible(find.text('Reveal private'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal private'));
    await tester.pumpAndSettle();

    expect(find.text('This is a private key'), findsOneWidget);
    expect(find.textContaining('Anyone who gets it'), findsOneWidget);
  });

  testWidgets('works in the dark theme', (tester) async {
    await tester.pumpScreen(const KeysScreen(), brightness: Brightness.dark);
    expect(find.text('No keys yet'), findsOneWidget);
    expectNoInvisibleText(tester);
  });

  testWidgets('survives a narrow window', (tester) async {
    final storage = await testStorage(
      seedWithKeys([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.pgp,
          label: 'A key with quite a long label indeed',
          publicMaterial: pgpPublicKey,
          fingerprint: pgpFingerprint,
          createdAt: DateTime.utc(2024),
          hasPrivate: true,
        ),
      ]),
    );
    await tester.pumpScreen(
      const KeysScreen(),
      storage: storage,
      size: const Size(360, 780),
    );
    expect(find.text('A key with quite a long label indeed'), findsOneWidget);
  });
}

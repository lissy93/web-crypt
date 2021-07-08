import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';
import 'package:web_crypt/crypto/pgp/pgp_keys.dart';
import 'package:web_crypt/features/decrypt/decrypt_screen.dart';

import '../support/harness.dart';

const _inputHint = 'Paste an encrypted message, or drop a file anywhere here';
const _secret = 'the secret words';
const _passphrase = 'open sesame';

Future<void> paste(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, _inputHint), text);
  await tester.pump();
}

Finder decryptButton() => find.widgetWithText(TextButton, 'Decrypt');

void main() {
  // built outside the fake clock a widget test runs under, since scrypt is
  // slow and its awaits never resolve in there
  late String agePassphraseMessage;
  late String pgpPassphraseMessage;
  late String pgpKeyMessage;
  late String ageRecipient;
  late String ageIdentity;
  late String ageKeyedMessage;
  late String protectedPgpKey;
  late String protectedPgpMessage;

  setUpAll(() async {
    agePassphraseMessage = utf8.decode(
      await collectBytes(
        const AgeFormat().encrypt(
          Stream.value(Uint8List.fromList(utf8.encode(_secret))),
          const EncryptOptions.withPassphrase(_passphrase, armor: true),
        ),
      ),
    );
    pgpPassphraseMessage = utf8.decode(
      await collectBytes(
        const PgpFormat().encrypt(
          Stream.value(Uint8List.fromList(utf8.encode(_secret))),
          const EncryptOptions.withPassphrase(_passphrase, armor: true),
        ),
      ),
    );
    final pgpKey = generatePgpKeyPair(name: 'Someone');
    pgpKeyMessage = utf8.decode(
      await collectBytes(
        const PgpFormat().encrypt(
          Stream.value(Uint8List.fromList(utf8.encode(_secret))),
          EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.pgp,
              material: pgpKey.publicKey,
              label: 'Someone',
            ),
          ], armor: true),
        ),
      ),
    );
    final agePair = await generateAgeKeyPair();
    ageRecipient = agePair.recipient;
    ageIdentity = agePair.identity;
    ageKeyedMessage = utf8.decode(
      await collectBytes(
        const AgeFormat().encrypt(
          Stream.value(Uint8List.fromList(utf8.encode(_secret))),
          EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.age,
              material: agePair.recipient,
              label: 'mine',
            ),
          ], armor: true),
        ),
      ),
    );

    final locked = generatePgpKeyPair(name: 'Locked', passphrase: 'key-pass');
    protectedPgpKey = locked.privateKey;
    protectedPgpMessage = utf8.decode(
      await collectBytes(
        const PgpFormat().encrypt(
          Stream.value(Uint8List.fromList(utf8.encode(_secret))),
          EncryptOptions.forRecipients([
            Recipient(
              format: CryptoFormatKind.pgp,
              material: locked.publicKey,
              label: 'Locked',
            ),
          ], armor: true),
        ),
      ),
    );
  });

  testWidgets('starts with an empty input and no prompts', (tester) async {
    await tester.pumpScreen(const DecryptScreen());

    expect(find.text('Decrypt'), findsWidgets);
    expect(find.text(_inputHint), findsOneWidget);
    expect(find.text('Choose a file'), findsOneWidget);
    expect(decryptButton(), findsNothing);
  });

  testWidgets('says what it found as soon as something is pasted', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, agePassphraseMessage);

    expect(find.textContaining('Found: age encrypted message'), findsOneWidget);
    expect(decryptButton(), findsOneWidget);
  });

  testWidgets('asks for a passphrase when the message needs one', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, pgpPassphraseMessage);

    expect(find.textContaining('Found: PGP message'), findsOneWidget);
    expect(find.textContaining('It needs the passphrase'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Passphrase'), findsOneWidget);
  });

  testWidgets('decrypts with the right passphrase', (tester) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, agePassphraseMessage);

    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      _passphrase,
    );
    await tester.pump();
    await tester.tap(decryptButton());
    await tester.pumpUntil(find.text('Decrypted'));

    expect(find.text(_secret), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a wrong passphrase says so and lets you retry', (tester) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, agePassphraseMessage);

    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'not it',
    );
    await tester.pump();
    await tester.tap(decryptButton());
    await tester.pumpUntil(find.text('That passphrase did not match.'));

    // the flow is still live, so a second attempt needs no restart
    expect(find.widgetWithText(TextField, 'Passphrase'), findsOneWidget);
    expect(decryptButton(), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      _passphrase,
    );
    await tester.pump();
    await tester.tap(decryptButton());
    await tester.pumpUntil(find.text('Decrypted'));
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('tampered input reports verification failure', (tester) async {
    // damage the ciphertext tail, so the header still parses, it asks for a
    // passphrase, and only then finds the payload broken
    final lines = agePassphraseMessage.trimRight().split('\n');
    final last = lines.length - 2;
    lines[last] = 'AAAA${lines[last].substring(4)}';

    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, lines.join('\n'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      _passphrase,
    );
    await tester.pump();
    await tester.tap(decryptButton());
    await tester.pumpUntil(find.textContaining('was not decrypted'));

    expect(
      find.text('This data failed verification and was not decrypted.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown input gets an inline hint, never a dialog', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, 'just some words I typed');

    expect(
      find.text("This doesn't look like an encrypted file or message."),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(decryptButton(), findsNothing);
  });

  testWidgets('a pasted key is recognised as a key, not a message', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, ageRecipient);

    expect(
      find.textContaining('age recipient (public key), not a message'),
      findsOneWidget,
    );
    expect(find.text('Go to Keys'), findsOneWidget);
  });

  testWidgets('a message needing a key explains rather than asking blindly', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, pgpKeyMessage);

    expect(find.textContaining('It needs a private key'), findsOneWidget);
    expect(find.text('Private key needed'), findsOneWidget);
    expect(find.text('You have no private keys yet.'), findsOneWidget);
  });

  testWidgets('a private key can be pasted in without saving it', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, ageKeyedMessage);

    expect(find.text('Private key needed'), findsOneWidget);
    await tester.tap(find.text('Paste a private key'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'AGE-SECRET-KEY-1… or an armored PGP private key',
      ),
      ageIdentity,
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Use this key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this key'));
    await tester.pumpUntil(find.widgetWithText(TextButton, 'Decrypt'));

    await tester.tap(find.widgetWithText(TextButton, 'Decrypt'));
    await tester.pumpUntil(find.text('Decrypted'));
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('a protected key asks for its own passphrase', (tester) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, protectedPgpMessage);

    await tester.tap(find.text('Paste a private key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'AGE-SECRET-KEY-1… or an armored PGP private key',
      ),
      protectedPgpKey,
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Use this key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this key'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Decrypt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Decrypt'));
    await tester.pumpUntil(find.text('Key passphrase'));

    expect(find.text('Key passphrase'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Key passphrase'),
      'key-pass',
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Decrypt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Decrypt'));
    await tester.pumpUntil(find.text('Decrypted'));
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('pasting a public key where a private one is needed says so', (
    tester,
  ) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, ageKeyedMessage);

    await tester.tap(find.text('Paste a private key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'AGE-SECRET-KEY-1… or an armored PGP private key',
      ),
      ageRecipient,
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Use this key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this key'));
    await tester.pumpAndSettle();

    expect(find.text('That is not a key we recognise.'), findsOneWidget);
  });

  testWidgets('clearing resets everything', (tester) async {
    await tester.pumpScreen(const DecryptScreen());
    await paste(tester, agePassphraseMessage);
    expect(find.textContaining('Found:'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Found:'), findsNothing);
    expect(decryptButton(), findsNothing);
  });

  testWidgets('works in the dark theme', (tester) async {
    await tester.pumpScreen(const DecryptScreen(), brightness: Brightness.dark);
    expect(find.text(_inputHint), findsOneWidget);
    expectNoInvisibleText(tester);
  });

  testWidgets('survives a narrow window', (tester) async {
    await tester.pumpScreen(const DecryptScreen(), size: const Size(360, 780));
    await paste(tester, agePassphraseMessage);
    expect(tester.takeException(), isNull);
  });
}

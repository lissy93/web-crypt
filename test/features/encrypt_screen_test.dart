import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/features/encrypt/encrypt_screen.dart';

import '../support/harness.dart';

Future<void> typeMessage(WidgetTester tester, String message) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Type or paste your message'),
    message,
  );
  await tester.pump();
}

Future<void> typePassphrase(WidgetTester tester, String value) async {
  await tester.enterText(find.widgetWithText(TextField, 'Passphrase'), value);
  await tester.pump();
  await tester.enterText(
    find.widgetWithText(TextField, 'Passphrase again'),
    value,
  );
  await tester.pump();
}

Finder encryptButton() => find.widgetWithText(TextButton, 'Encrypt');

void main() {
  testWidgets('opens on the message tab with passphrase mode', (tester) async {
    await tester.pumpScreen(const EncryptScreen());

    expect(find.text('Encrypt'), findsWidgets);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Type or paste your message'), findsOneWidget);
    expect(find.text('Passphrase'), findsWidgets);
  });

  testWidgets('encrypts a message and shows armored output', (tester) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello there');
    await typePassphrase(tester, 'a decent passphrase here');

    await tester.tap(encryptButton());
    await tester.pumpUntil(find.text('Encrypted'));

    expect(find.text('Encrypted'), findsOneWidget);
    final output = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(output.data, startsWith('-----BEGIN AGE ENCRYPTED FILE-----'));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);
  });

  testWidgets('start over clears the output', (tester) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello');
    await typePassphrase(tester, 'a decent passphrase here');
    await tester.tap(encryptButton());
    await tester.pumpUntil(find.text('Start over'));

    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();

    expect(find.text('Encrypted'), findsNothing);
    expect(find.text('Type or paste your message'), findsOneWidget);
  });

  testWidgets('mismatched passphrases block encryption', (tester) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello');
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'one thing',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase again'),
      'another thing',
    );
    await tester.pump();

    await tester.tap(encryptButton());
    await tester.pumpAndSettle();

    expect(find.text('The two do not match.'), findsOneWidget);
    expect(find.text('Encrypted'), findsNothing);
  });

  testWidgets('an empty passphrase is refused with words, not a crash', (
    tester,
  ) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello');
    await tester.tap(encryptButton());
    await tester.pumpAndSettle();

    expect(find.text('Enter a passphrase.'), findsOneWidget);
  });

  testWidgets('a weak passphrase warns but still works', (tester) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello');
    await typePassphrase(tester, 'abc');

    expect(find.text('That passphrase is easy to guess.'), findsOneWidget);

    await tester.tap(encryptButton());
    await tester.pumpUntil(find.text('Encrypted'));
    expect(find.text('Encrypted'), findsOneWidget);
  });

  testWidgets('recipient mode with no recipients explains itself', (
    tester,
  ) async {
    await tester.pumpScreen(const EncryptScreen());
    await typeMessage(tester, 'hello');
    await tester.tap(find.text('Recipients'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nobody can open this yet. Add at least one recipient.'),
      findsOneWidget,
    );

    await tester.tap(encryptButton());
    await tester.pumpUntil(find.text('Add at least one recipient first.'));
    expect(find.text('Add at least one recipient first.'), findsOneWidget);
  });

  testWidgets('the file tab shows a drop zone and an armor toggle', (
    tester,
  ) async {
    await tester.pumpScreen(const EncryptScreen());
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Drop files here, or browse'), findsOneWidget);
    expect(find.text('Text-safe output'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the last format and mode are remembered', (tester) async {
    final storage = await testStorage();
    await storage.setLastFormat(CryptoFormatKind.pgp);
    await storage.setLastMode(EncryptMode.recipients);

    await tester.pumpScreen(const EncryptScreen(), storage: storage);

    expect(
      find.text('Nobody can open this yet. Add at least one recipient.'),
      findsOneWidget,
    );
    // choosing PGP should offer a PGP key block as the paste hint
    await tester.tap(find.text('Paste a key'));
    await tester.pumpAndSettle();
    expect(find.text('-----BEGIN PGP PUBLIC KEY BLOCK-----'), findsOneWidget);
  });

  testWidgets('changing format is written back to storage', (tester) async {
    final storage = await testStorage();
    await tester.pumpScreen(const EncryptScreen(), storage: storage);

    await tester.tap(find.text('PGP'));
    await tester.pumpAndSettle();

    expect(storage.lastFormat, CryptoFormatKind.pgp);
  });

  testWidgets('PGP output is armored too', (tester) async {
    final storage = await testStorage();
    await storage.setLastFormat(CryptoFormatKind.pgp);
    await tester.pumpScreen(const EncryptScreen(), storage: storage);

    await typeMessage(tester, 'hello pgp');
    await typePassphrase(tester, 'a decent passphrase here');
    await tester.tap(encryptButton());
    await tester.pumpUntil(find.text('Encrypted'));

    final output = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(
      FormatDetector.detect(output.data!.codeUnits),
      DetectedFormat.pgpArmoredMessage,
    );
  });

  testWidgets('works in the dark theme too', (tester) async {
    await tester.pumpScreen(const EncryptScreen(), brightness: Brightness.dark);
    expect(find.text('Type or paste your message'), findsOneWidget);
    expectNoInvisibleText(tester);
  });

  testWidgets('survives a narrow window', (tester) async {
    await tester.pumpScreen(const EncryptScreen(), size: const Size(360, 780));
    expect(tester.takeException(), isNull);
    expect(find.text('Type or paste your message'), findsOneWidget);
  });

  testWidgets('survives 200 percent text scaling', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpScreen(const EncryptScreen(), size: const Size(800, 1400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every control is reachable with the keyboard', (tester) async {
    await tester.pumpScreen(const EncryptScreen());

    final focused = <String>{};
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final node = FocusManager.instance.primaryFocus;
      if (node != null) {
        focused.add(node.debugLabel ?? node.hashCode.toString());
      }
    }
    expect(focused.length, greaterThan(3));
    expect(tester.takeException(), isNull);
  });
}

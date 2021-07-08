import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_crypt/app/app.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/services/storage_service.dart';

/// whole flows through the real app: launch it, click through it, and check
/// that what comes out the other end is what went in.
///
/// binding-agnostic on purpose. `flutter test` runs these headless as part of
/// the normal suite, and `integration_test/app_test.dart` runs the same flows
/// on a real device
void main() {
  Future<void> launch(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(StorageService(prefs, null)),
        ],
        child: const WebCryptApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// modal sheets close on Escape, the same way a keyboard user closes them
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  /// crypto runs in a real isolate, which the fake clock does not advance
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw StateError('never found: $finder');
  }

  Future<String> encryptMessage(
    WidgetTester tester, {
    required String message,
    required String passphrase,
    required String format,
  }) async {
    await tester.tap(find.text('Encrypt').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(format));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Type or paste your message'),
      message,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      passphrase,
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase again'),
      passphrase,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Encrypt'));
    await waitFor(tester, find.text('Encrypted'));

    final output = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    return output.data!;
  }

  Future<void> decryptMessage(
    WidgetTester tester, {
    required String ciphertext,
    required String passphrase,
    required String expected,
  }) async {
    await tester.tap(find.text('Decrypt').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Paste an encrypted message, or drop a file anywhere here',
      ),
      ciphertext,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      passphrase,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Decrypt'));
    await waitFor(tester, find.text('Decrypted'));

    expect(find.text(expected), findsOneWidget);
  }

  for (final format in ['age', 'PGP']) {
    testWidgets('$format: a message survives a full trip through the UI', (
      tester,
    ) async {
      const message = 'Meet me at the usual place.';
      const passphrase = 'correct horse battery staple';

      await launch(tester);
      final ciphertext = await encryptMessage(
        tester,
        message: message,
        passphrase: passphrase,
        format: format,
      );
      expect(ciphertext, contains('-----BEGIN'));

      await decryptMessage(
        tester,
        ciphertext: ciphertext,
        passphrase: passphrase,
        expected: message,
      );
    });
  }

  testWidgets('generate a key, then encrypt to it and read it back', (
    tester,
  ) async {
    await launch(tester);

    await tester.tap(find.text('Keys').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This session only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await waitFor(tester, find.text('Recipient'));

    await closeSheet(tester);
    expect(find.text('private'), findsOneWidget);

    await tester.tap(find.text('Encrypt').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipients'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type or paste your message'),
      'for my own eyes',
    );
    await tester.pump();

    await tester.tap(find.text('From keyring'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Encrypt'));
    await waitFor(tester, find.text('Encrypted'));
    final ciphertext = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data!;

    await tester.tap(find.text('Decrypt').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Paste an encrypted message, or drop a file anywhere here',
      ),
      ciphertext,
    );
    await tester.pumpAndSettle();

    // the key is unlocked in this session, so it is tried without being asked
    await tester.tap(find.widgetWithText(TextButton, 'Decrypt'));
    await waitFor(tester, find.text('Decrypted'));
    expect(find.text('for my own eyes'), findsOneWidget);
  });

  testWidgets('what is stored survives a restart, and clearing empties it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs, null);

    Future<void> start() async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const WebCryptApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await start();

    await tester.tap(find.text('Keys').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Or paste it here'),
      'age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Import').last);
    await waitFor(tester, find.text('Recipient'));
    await closeSheet(tester);

    expect(storage.loadPublicKeys(), hasLength(1));

    // a restart is a fresh widget tree over the same storage
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await start();
    await tester.tap(find.text('Keys').first);
    await tester.pumpAndSettle();
    expect(find.text('No keys yet'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear everything'));
    await tester.pumpAndSettle();

    expect(storage.loadPublicKeys(), isEmpty);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/features/settings/about_panel.dart';
import 'package:web_crypt/features/settings/settings_screen.dart';
import 'package:web_crypt/main.dart';
import 'package:web_crypt/services/storage_service.dart';

import '../support/harness.dart';

void main() {
  testWidgets('shows theme, keyring and data sections', (tester) async {
    await tester.pumpScreen(const SettingsScreen());

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Keyring'), findsOneWidget);
    expect(find.text('Local data'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('choosing a theme is written to storage', (tester) async {
    final storage = await testStorage();
    await tester.pumpScreen(const SettingsScreen(), storage: storage);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(storage.theme, ThemeChoice.dark);
  });

  testWidgets('the about panel says what it protects and links plainly', (
    tester,
  ) async {
    await tester.pumpScreen(const SettingsScreen());

    expect(find.textContaining('no network requests'), findsOneWidget);
    expect(find.text('What it protects'), findsOneWidget);
    expect(
      find.textContaining('cannot protect you from a device or browser'),
      findsOneWidget,
    );
    expect(find.text('Licences'), findsOneWidget);
    // links are text, not buttons, so nothing here can open a connection
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('clearing all data asks first and names what goes', (
    tester,
  ) async {
    final storage = await testStorage({
      'flutter.keys.public': jsonEncode([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.age,
          label: 'Mine',
          publicMaterial: 'age1abc',
          fingerprint: 'age1abc',
          createdAt: DateTime.utc(2024),
          hasPrivate: true,
        ).toJson(),
      ]),
    });
    await tester.pumpScreen(const SettingsScreen(), storage: storage);

    await tester.tap(find.text('Clear all local data'));
    await tester.pumpAndSettle();

    expect(find.text('Clear all local data?'), findsOneWidget);
    expect(find.textContaining('1 private one(s)'), findsOneWidget);
    expect(find.textContaining('There is no undo'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.loadPublicKeys(), hasLength(1));
  });

  testWidgets('confirming clears everything', (tester) async {
    final storage = await testStorage({
      'flutter.theme': ThemeChoice.dark.name,
      'flutter.keys.public': jsonEncode([
        KeyEntry(
          id: '1',
          format: CryptoFormatKind.age,
          label: 'Mine',
          publicMaterial: 'age1abc',
          fingerprint: 'age1abc',
          createdAt: DateTime.utc(2024),
        ).toJson(),
      ]),
    });
    await tester.pumpScreen(const SettingsScreen(), storage: storage);

    await tester.tap(find.text('Clear all local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear everything'));
    await tester.pumpAndSettle();

    expect(storage.loadPublicKeys(), isEmpty);
    expect(storage.theme, ThemeChoice.system);
    expect(find.text('Local data cleared'), findsOneWidget);
  });

  testWidgets('a clear that storage refuses says so', (tester) async {
    SharedPreferences.setMockInitialValues({'theme': ThemeChoice.dark.name});
    final prefs = RefusingPrefs(await SharedPreferences.getInstance())
      ..refused.add('theme');
    final storage = StorageService(prefs, null);
    await tester.pumpScreen(const SettingsScreen(), storage: storage);

    await tester.tap(find.text('Clear all local data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear everything'));
    await tester.pumpAndSettle();

    expect(find.text('Local data cleared'), findsNothing);
    expect(
      find.text('That change could not be stored on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('an untouched keyring explains it will ask later', (
    tester,
  ) async {
    await tester.pumpScreen(const SettingsScreen());
    expect(
      find.textContaining('You will be asked how to keep them'),
      findsOneWidget,
    );
    expect(find.text('Change master password'), findsNothing);
  });

  testWidgets('a locked keyring says so', (tester) async {
    final storage = await testStorage({
      'flutter.keys.mode': KeyringMode.masterPassword.name,
      'flutter.keys.vault':
          '-----BEGIN AGE ENCRYPTED FILE-----\nZm9v\n'
          '-----END AGE ENCRYPTED FILE-----',
    });
    await tester.pumpScreen(const SettingsScreen(), storage: storage);

    expect(find.textContaining('Locked.'), findsOneWidget);
  });

  testWidgets('works in the dark theme', (tester) async {
    await tester.pumpScreen(
      const SettingsScreen(),
      brightness: Brightness.dark,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expectNoInvisibleText(tester);
  });

  testWidgets('survives a narrow window', (tester) async {
    await tester.pumpScreen(const SettingsScreen(), size: const Size(360, 780));
    expect(find.text('Appearance'), findsOneWidget);
  });

  test('the bundled font licences reach the licence page', () async {
    registerFontLicences();
    final entries = await LicenseRegistry.licenses.toList();
    for (final family in ['Inter', 'JetBrains Mono']) {
      final entry = entries.firstWhere(
        (candidate) => candidate.packages.contains(family),
        orElse: () => throw StateError('$family has no licence registered'),
      );
      final text = entry.paragraphs.map((p) => p.text).join(' ');
      expect(text, contains('SIL OPEN FONT LICENSE'));
    }
  });

  test('the version shown matches pubspec', () {
    final declared = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('version:'))
        .split(':')
        .last
        .trim()
        .split('+')
        .first;
    expect(appVersion, declared);
  });
}

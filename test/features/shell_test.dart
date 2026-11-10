import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/app/app.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/services/file_service.dart';

import '../support/harness.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(await testStorage()),
      ],
      child: const WebCryptApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Encrypt', (tester) async {
    await pumpApp(tester);
    expect(find.text('Type or paste your message'), findsOneWidget);
  });

  testWidgets('a wide window uses a rail', (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('a screen reader can reach the rail beside the page', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    expect(find.semantics.byLabel('web-crypt'), findsOne);
    for (final tab in ['Encrypt', 'Decrypt', 'Keys']) {
      expect(find.semantics.byLabel(RegExp('^$tab\nTab')), findsOne);
    }
    expect(
      find.semantics.byPredicate((node) => node.tooltip == 'Settings'),
      findsOne,
    );
    expect(find.semantics.byLabel('Settings'), findsNothing);
    handle.dispose();
  });

  testWidgets('a narrow window uses a bottom bar', (tester) async {
    await pumpApp(tester, size: const Size(700, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('the breakpoint is where the spec says', (tester) async {
    await pumpApp(tester, size: const Size(Layout.wideBreakpoint, 900));
    expect(find.byType(NavigationRail), findsOneWidget);

    await pumpApp(tester, size: const Size(Layout.wideBreakpoint - 1, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('all three destinations plus settings are reachable', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Decrypt').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Paste an encrypted message, or drop a file anywhere here'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keys').first);
    await tester.pumpAndSettle();
    expect(find.text('No keys yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Encrypt').first);
    await tester.pumpAndSettle();
    expect(find.text('Type or paste your message'), findsOneWidget);
  });

  testWidgets('each page names itself in the title', (tester) async {
    await pumpApp(tester);
    String title() => tester.widget<Title>(find.byType(Title).last).title;
    expect(title(), 'Encrypt · web-crypt');

    await tester.tap(find.text('Keys').first);
    await tester.pumpAndSettle();
    expect(title(), 'Keys · web-crypt');

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(title(), 'Settings · web-crypt');
  });

  group('a file opened from the OS', () {
    final bytes = File('test/fixtures/pgp-symmetric-v4.gpg').readAsBytesSync();
    final file = PickedFile(name: 'note.gpg', size: bytes.length, bytes: bytes);
    const asked = 'The one used when this was encrypted.';

    void open(WidgetTester tester, [PickedFile? picked]) {
      final app = tester.element(find.byType(WebCryptApp));
      ProviderScope.containerOf(
        app,
      ).read(openedFileProvider.notifier).open(picked ?? file);
    }

    testWidgets('waits for Decrypt to open', (tester) async {
      await pumpApp(tester);
      open(tester);
      await tester.pumpAndSettle();
      expect(find.text(asked), findsNothing);

      await tester.tap(find.text('Decrypt').first);
      await tester.pumpAndSettle();
      expect(find.text('note.gpg'), findsOneWidget);
      expect(find.text(asked), findsOneWidget);
    });

    testWidgets('goes straight in when Decrypt is showing', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Decrypt').first);
      await tester.pumpAndSettle();

      open(tester);
      await tester.pumpAndSettle();
      expect(find.text('note.gpg'), findsOneWidget);
      expect(find.text(asked), findsOneWidget);
    });

    testWidgets('waits for the last file to finish loading', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Decrypt').first);
      await tester.pumpAndSettle();

      open(tester);
      final later = PickedFile(
        name: 'later.gpg',
        size: bytes.length,
        bytes: bytes,
      );
      open(tester, later);
      await tester.pumpAndSettle();
      expect(find.text('later.gpg'), findsOneWidget);
    });
  });

  testWidgets('content is centred and capped in width', (tester) async {
    await pumpApp(tester, size: const Size(2400, 900));
    final box = tester.getRect(
      find
          .ancestor(
            of: find.text('Type or paste your message'),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(box.width, lessThanOrEqualTo(Layout.contentMaxWidth + 1));
  });

  testWidgets('nothing overflows down to 360 px', (tester) async {
    await pumpApp(tester, size: const Size(360, 780));
    expect(tester.takeException(), isNull);
  });
}

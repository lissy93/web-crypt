import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/app/app.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/spacing.dart';

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

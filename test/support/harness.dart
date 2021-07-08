import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/services/storage_service.dart';

/// real preferences over a fake store, so nothing is faked that could just
/// run for real. seeding this is how tests set up state
Future<StorageService> testStorage([
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return StorageService(prefs, null);
}

Widget _wrap(
  Widget child, {
  required StorageService storage,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
    child: MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

extension PumpApp on WidgetTester {
  Future<void> pumpScreen(
    Widget child, {
    StorageService? storage,
    Brightness brightness = Brightness.light,
    Size size = const Size(1000, 900),
  }) async {
    view.physicalSize = size;
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await pumpWidget(
      _wrap(
        child,
        storage: storage ?? await testStorage(),
        brightness: brightness,
      ),
    );
    await pumpAndSettle();
  }
}

/// fails if any painted text is effectively invisible, a cheap stand-in for a
/// full contrast audit
void expectNoInvisibleText(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final colour = text.style?.color;
    if (colour == null) continue;
    expect(
      colour.a,
      greaterThan(0.3),
      reason: 'text "${text.data}" is nearly transparent',
    );
  }
}

/// lets real time pass, then rebuilds, until the expected thing appears. a
/// widget test's fake clock does not advance a real isolate, and a spinner
/// stops `pumpAndSettle` from ever returning
extension PumpUntil on WidgetTester {
  Future<void> pumpUntil(
    Finder finder, {
    Duration step = const Duration(milliseconds: 50),
    int maxSteps = 200,
  }) async {
    for (var i = 0; i < maxSteps; i++) {
      await runAsync(() => Future<void>.delayed(step));
      await pump(step);
      if (finder.evaluate().isNotEmpty) return;
    }
    throw StateError('never found: $finder');
  }
}

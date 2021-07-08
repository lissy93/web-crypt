import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/features/decrypt/decrypt_screen.dart';
import 'package:web_crypt/features/encrypt/encrypt_screen.dart';
import 'package:web_crypt/features/keys/keys_screen.dart';
import 'package:web_crypt/features/settings/settings_screen.dart';

import '../support/harness.dart';

/// Flutter ships the WCAG checks, so run those
void main() {
  final screens = <String, Widget>{
    'Encrypt': const EncryptScreen(),
    'Decrypt': const DecryptScreen(),
    'Keys': const KeysScreen(),
    'Settings': const SettingsScreen(),
  };

  for (final entry in screens.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('${entry.key} passes the guidelines in ${brightness.name}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpScreen(entry.value, brightness: brightness);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // 44px is the iOS threshold. settings is exempt, its About urls are
        // selectable text with a longPress action, not controls
        if (entry.key != 'Settings') {
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        }

        handle.dispose();
      });
    }
  }
}

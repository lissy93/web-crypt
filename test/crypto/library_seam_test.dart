import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// the vendored forks are the part of this app most likely to be swapped out,
/// so they are only allowed to be named behind the format adapters. keeping
/// that boundary is what makes a swap a small job rather than a rewrite
void main() {
  const adapters = {
    'lib/crypto/age/age_format.dart',
    'lib/crypto/age/age_keys.dart',
    'lib/crypto/pgp/pgp_format.dart',
    'lib/crypto/pgp/pgp_keys.dart',
  };

  final vendored = RegExp(
    r"^\s*(import|export)\s+'package:(dart_pg|dage)/",
    multiLine: true,
  );

  test('nothing outside the format adapters touches dage or dart_pg', () {
    final offenders =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path.replaceAll(r'\', '/'))
            .where((path) => path.endsWith('.dart'))
            .where((path) => !adapters.contains(path))
            .where((path) => vendored.hasMatch(File(path).readAsStringSync()))
            .toList(growable: false)
          ..sort();

    expect(
      offenders,
      isEmpty,
      reason:
          'these reach past lib/crypto for a vendored type. wrap it in the '
          'adapter instead, or add the file to the allowlist on purpose',
    );
  });

  test('every adapter in the allowlist still exists', () {
    for (final path in adapters) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is allowlisted but missing, so the guard has gone stale',
      );
    }
  });
}

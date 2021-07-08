// a thin CLI over lib/crypto so the interop scripts drive exactly the code
// the app runs, and is not shipped with it
import 'dart:convert';
import 'dart:io';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';

const _service = CryptoService();

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) _fail('usage: harness <command> [options]');
  final command = argv.first;
  final args = _parseArgs(argv.skip(1).toList());
  try {
    switch (command) {
      case 'gen-age-key':
        await _genAgeKey(args);
      case 'gen-pgp-key':
        await _genPgpKey(args);
      case 'encrypt':
        await _encrypt(args);
      case 'decrypt':
        await _decrypt(args);
      case 'detect':
        await _detect(args);
      default:
        _fail('unknown command: $command');
    }
  } on AppException catch (error) {
    _fail('app-error: ${error.runtimeType}');
  }
}

Future<void> _genAgeKey(_Args args) async {
  final pair = await _service.generateKey(format: CryptoFormatKind.age);
  final out = args.optional('out');
  if (out != null) {
    File(out).writeAsStringSync(
      ageIdentityFile(
        pair.privateMaterial,
        pair.publicMaterial,
        DateTime.now(),
      ),
    );
  }
  stdout.writeln(
    jsonEncode({
      'recipient': pair.publicMaterial,
      'identity': pair.privateMaterial,
    }),
  );
}

Future<void> _genPgpKey(_Args args) async {
  final expiryDays = args.optional('expiry-days');
  final pair = await _service.generateKey(
    format: CryptoFormatKind.pgp,
    name: args.optional('name') ?? '',
    email: args.optional('email') ?? '',
    passphrase: args.optional('passphrase'),
    expiry: expiryDays == null ? null : Duration(days: int.parse(expiryDays)),
  );
  final publicOut = args.optional('public-out');
  final privateOut = args.optional('private-out');
  if (publicOut != null) File(publicOut).writeAsStringSync(pair.publicMaterial);
  if (privateOut != null) {
    File(privateOut).writeAsStringSync(pair.privateMaterial);
  }
  stdout.writeln(
    jsonEncode({
      'fingerprint': pair.fingerprint,
      'userId': pair.userId,
      'protected': pair.isProtected,
    }),
  );
}

Future<void> _encrypt(_Args args) async {
  final format = args.require('format') == 'age'
      ? CryptoFormatKind.age
      : CryptoFormatKind.pgp;
  final mode = args.require('mode') == 'pass'
      ? EncryptMode.passphrase
      : EncryptMode.recipients;
  final recipients = <Recipient>[
    for (final value in args.all('recipient'))
      Recipient(format: format, material: _materialFor(value), label: 'cli'),
  ];
  final options = EncryptOptions(
    mode: mode,
    passphrase: args.optional('pass'),
    recipients: recipients,
    armor: args.flag('armor'),
    filename: args.optional('filename'),
  );

  final source = args.require('in');
  final target = args.require('out');
  if (args.flag('bytes')) {
    final bytes = await _service.encryptBytes(
      format: format,
      input: File(source).readAsBytesSync(),
      options: options,
    );
    File(target).writeAsBytesSync(bytes);
  } else {
    await _service.encryptFile(
      format: format,
      sourcePath: source,
      targetPath: target,
      options: options,
    );
  }
  stdout.writeln('ok');
}

Future<void> _decrypt(_Args args) async {
  final identities = <Identity>[
    for (final value in args.all('age-identity'))
      Identity(format: CryptoFormatKind.age, material: _materialFor(value)),
    for (final value in args.all('pgp-identity'))
      Identity(
        format: CryptoFormatKind.pgp,
        material: _materialFor(value),
        passphrase: args.optional('key-pass'),
      ),
  ];

  final source = args.require('in');
  final target = args.require('out');
  final DecryptMetadata metadata;
  if (args.flag('bytes')) {
    final outcome = await _service.decryptBytes(
      input: File(source).readAsBytesSync(),
      passphrase: args.optional('pass'),
      identities: identities,
    );
    File(target).writeAsBytesSync(outcome.bytes);
    metadata = outcome.metadata;
  } else {
    metadata = await _service.decryptFile(
      sourcePath: source,
      targetPath: target,
      passphrase: args.optional('pass'),
      identities: identities,
    );
  }
  stdout.writeln(jsonEncode({'filename': metadata.filename}));
}

Future<void> _detect(_Args args) async {
  final file = File(args.require('in'));
  final length = file.lengthSync();
  final head = file.openSync().readSync(
    length < detectionHeadSize ? length : detectionHeadSize,
  );
  stdout.writeln(FormatDetector.detect(head).name);
}

/// values are either literal (`age1...`) or `@path` to read from a file
String _materialFor(String value) =>
    value.startsWith('@') ? File(value.substring(1)).readAsStringSync() : value;

Never _fail(String message) {
  stderr.writeln(message);
  exit(2);
}

class _Args {
  _Args(this._values, this._flags);

  final Map<String, List<String>> _values;
  final Set<String> _flags;

  String require(String name) =>
      _values[name]?.first ?? _fail('missing --$name');

  String? optional(String name) => _values[name]?.first;

  List<String> all(String name) => _values[name] ?? const [];

  bool flag(String name) => _flags.contains(name);
}

_Args _parseArgs(List<String> argv) {
  final values = <String, List<String>>{};
  final flags = <String>{};
  for (var i = 0; i < argv.length; i++) {
    final token = argv[i];
    if (!token.startsWith('--')) _fail('unexpected argument: $token');
    final name = token.substring(2);
    if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      values.putIfAbsent(name, () => []).add(argv[++i]);
    } else {
      flags.add(name);
    }
  }
  return _Args(values, flags);
}

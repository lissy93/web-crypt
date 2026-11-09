import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/format.dart';

/// file jobs stream through an isolate on native and report bytes as they go,
/// which is the on-disk path the in-memory tests never take
void main() {
  const service = CryptoService();
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('web-crypt-progress');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  File fixture(String name, int length) {
    final file = File(p.join(work.path, name));
    file.writeAsBytesSync(
      Uint8List.fromList(List.generate(length, (i) => (i * 13 + 5) % 256)),
    );
    return file;
  }

  test('encrypting a file reports progress and round trips', () async {
    const size = 900 * 1024;
    final source = fixture('source.bin', size);
    final sealed = p.join(work.path, 'source.bin.age');
    final back = p.join(work.path, 'back.bin');

    final encryptProgress = <int>[];
    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: source.path,
      targetPath: sealed,
      options: const EncryptOptions.withPassphrase('pw'),
      onProgress: encryptProgress.add,
    );

    expect(File(sealed).existsSync(), isTrue);
    expect(encryptProgress, isNotEmpty, reason: 'no progress was reported');
    expect(encryptProgress, orderedEquals(List.of(encryptProgress)..sort()));
    expect(encryptProgress.last, size, reason: 'the final report is the total');

    final decryptProgress = <int>[];
    await service.decryptFile(
      sourcePath: sealed,
      targetPath: back,
      passphrase: 'pw',
      onProgress: decryptProgress.add,
    );

    expect(decryptProgress, isNotEmpty);
    expect(File(back).readAsBytesSync(), source.readAsBytesSync());
  });

  // the app's callbacks hold things an isolate cannot copy, and so does this
  test('progress can come from a closure an isolate cannot copy', () async {
    const size = 4096;
    final finished = Completer<int>();
    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: fixture('held.bin', size).path,
      targetPath: p.join(work.path, 'held.age'),
      options: const EncryptOptions.withPassphrase('pw'),
      onProgress: (processed) {
        if (processed == size && !finished.isCompleted) {
          finished.complete(processed);
        }
      },
    );
    expect(await finished.future, size);
  });

  test('a file job with no progress callback still works', () async {
    final source = fixture('quiet.bin', 4096);
    final sealed = p.join(work.path, 'quiet.age');
    final back = p.join(work.path, 'quiet.back');

    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: source.path,
      targetPath: sealed,
      options: const EncryptOptions.withPassphrase('pw'),
    );
    await service.decryptFile(
      sourcePath: sealed,
      targetPath: back,
      passphrase: 'pw',
    );
    expect(File(back).readAsBytesSync(), source.readAsBytesSync());
  });

  test('a job that fails before any output leaves the target alone', () async {
    final source = fixture('secret.bin', 8192);
    final sealed = p.join(work.path, 'secret.age');
    final existing = File(p.join(work.path, 'report.pdf'))
      ..writeAsStringSync('keep me');

    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: source.path,
      targetPath: sealed,
      options: const EncryptOptions.withPassphrase('right'),
    );

    await expectLater(
      service.decryptFile(
        sourcePath: sealed,
        targetPath: existing.path,
        passphrase: 'wrong',
      ),
      throwsA(isA<WrongPassphrase>()),
    );
    await expectLater(
      service.encryptFile(
        format: CryptoFormatKind.age,
        sourcePath: source.path,
        targetPath: existing.path,
        options: const EncryptOptions.forRecipients([]),
      ),
      throwsA(isA<NoRecipients>()),
    );
    expect(existing.readAsStringSync(), 'keep me');
  });

  test(
    'a target that cannot be opened is left alone',
    () async {
      final existing = File(p.join(work.path, 'readonly.age'))
        ..writeAsStringSync('keep me');
      Process.runSync('chmod', ['a-w', existing.path]);

      await expectLater(
        service.encryptFile(
          format: CryptoFormatKind.age,
          sourcePath: fixture('plain.bin', 4096).path,
          targetPath: existing.path,
          options: const EncryptOptions.withPassphrase('pw'),
        ),
        throwsA(isA<FileAccessFailed>()),
      );
      expect(existing.readAsStringSync(), 'keep me');
    },
    skip: Platform.isWindows ? 'needs chmod' : null,
  );

  test('a job that fails partway removes what it wrote', () async {
    // four chunks, so three are written before the last one fails
    final source = fixture('long.bin', 200 * 1024);
    final sealed = File(p.join(work.path, 'long.age'));
    final back = File(p.join(work.path, 'long.back'));

    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: source.path,
      targetPath: sealed.path,
      options: const EncryptOptions.withPassphrase('pw'),
    );
    final bytes = sealed.readAsBytesSync();
    bytes[bytes.length - 1] ^= 0x01;
    sealed.writeAsBytesSync(bytes);

    await expectLater(
      service.decryptFile(
        sourcePath: sealed.path,
        targetPath: back.path,
        passphrase: 'pw',
      ),
      throwsA(isA<AppException>()),
    );
    expect(
      back.existsSync(),
      isFalse,
      reason: 'a half-written file still looks like a real one',
    );
  });

  test('PGP file jobs work on disk too', () async {
    final source = fixture('doc.bin', 200 * 1024);
    final sealed = p.join(work.path, 'doc.gpg');
    final back = p.join(work.path, 'doc.back');

    await service.encryptFile(
      format: CryptoFormatKind.pgp,
      sourcePath: source.path,
      targetPath: sealed,
      options: const EncryptOptions.withPassphrase('pw', filename: 'doc.bin'),
    );
    final metadata = await service.decryptFile(
      sourcePath: sealed,
      targetPath: back,
      passphrase: 'pw',
    );

    expect(metadata.filename, 'doc.bin');
    expect(File(back).readAsBytesSync(), source.readAsBytesSync());
  });

  test('countingBytes reports as it goes and once at the end', () async {
    final chunks = List.generate(10, (_) => List.filled(100 * 1024, 7));
    final reports = <int>[];
    final out = await collectBytes(
      countingBytes(Stream.fromIterable(chunks), reports.add),
    );
    expect(out.length, 10 * 100 * 1024);
    expect(reports, isNotEmpty);
    expect(reports.last, out.length);
    expect(reports, orderedEquals(List.of(reports)..sort()));
  });
}

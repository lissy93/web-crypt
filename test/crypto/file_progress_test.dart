import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  // the controllers report from a closure over a notifier, which an isolate
  // cannot copy. a closure over a future cannot be copied either
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

  test('a failed file job leaves no half-written output', () async {
    final source = fixture('secret.bin', 8192);
    final sealed = p.join(work.path, 'secret.age');
    final back = p.join(work.path, 'back.bin');

    await service.encryptFile(
      format: CryptoFormatKind.age,
      sourcePath: source.path,
      targetPath: sealed,
      options: const EncryptOptions.withPassphrase('right'),
    );

    await expectLater(
      service.decryptFile(
        sourcePath: sealed,
        targetPath: back,
        passphrase: 'wrong',
      ),
      throwsA(anything),
    );
    expect(
      File(back).existsSync(),
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

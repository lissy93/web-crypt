import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/features/decrypt/decrypt_controller.dart';
import 'package:web_crypt/services/file_service.dart';

import '../support/harness.dart';

/// a decrypted file drops the container extension, so `report.pdf.age` saves
/// as `report.pdf`
class _RecordingFiles extends FileService {
  const _RecordingFiles(this.suggested);

  final List<String> suggested;

  @override
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    suggested.add(suggestedName);
    return '/somewhere/$suggestedName';
  }
}

void main() {
  late Uint8List sealed;

  setUpAll(() async {
    sealed = await collectBytes(
      const AgeFormat().encrypt(
        Stream.value(Uint8List.fromList(utf8.encode('the contents'))),
        const EncryptOptions.withPassphrase('pw'),
      ),
    );
  });

  Future<List<String>> saveAfterDecrypting(String sourceName) async {
    final suggested = <String>[];
    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(await testStorage()),
        fileServiceProvider.overrideWithValue(_RecordingFiles(suggested)),
      ],
    );
    addTearDown(container.dispose);
    // the provider auto-disposes, so hold it open as a mounted screen would
    container.listen(decryptProvider, (_, _) {});

    final controller = container.read(decryptProvider.notifier);
    await controller.onFile(
      PickedFile(name: sourceName, size: sealed.length, bytes: sealed),
    );
    await controller.decrypt(passphrase: 'pw');
    await controller.saveOutputAsFile();
    return suggested;
  }

  test('the container extension comes off', () async {
    expect(await saveAfterDecrypting('report.pdf.age'), ['report.pdf']);
    expect(await saveAfterDecrypting('notes.txt.gpg'), ['notes.txt']);
    expect(await saveAfterDecrypting('MESSAGE.ASC'), ['MESSAGE']);
  });

  test('a name with no container extension still changes', () async {
    // saving over the file that was just read would be a nasty surprise
    expect(await saveAfterDecrypting('mystery'), ['mystery.decrypted']);
  });
}

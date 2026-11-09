import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/features/decrypt/decrypt_controller.dart';
import 'package:web_crypt/services/file_service.dart';

import '../support/harness.dart';

/// a file on disk that tracks the most bytes any single read returned
class _Watched extends PickedFile {
  _Watched({required super.name, required super.size, super.path});

  var mostRead = 0;

  Uint8List _noted(Uint8List bytes) {
    mostRead = max(mostRead, bytes.length);
    return bytes;
  }

  @override
  Future<Uint8List> read() async => _noted(await super.read());

  @override
  Future<Uint8List> readHead(int count) async =>
      _noted(await super.readHead(count));
}

void main() {
  test('a big file is sniffed from its head and left on disk', () async {
    final dir = Directory.systemTemp.createTempSync('web-crypt-head');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sealed = await collectBytes(
      const AgeFormat().encrypt(
        Stream.value(Uint8List(2 * SizeLimits.message)),
        const EncryptOptions.withPassphrase('pw'),
      ),
    );
    final file = File(p.join(dir.path, 'big.age'))..writeAsBytesSync(sealed);

    // the size a picker reports can be stale, so it is not what decides
    for (final reported in [sealed.length, 0]) {
      final picked = _Watched(name: 'big.age', size: reported, path: file.path);
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(await testStorage()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(decryptProvider, (_, _) {});
      await container.read(decryptProvider.notifier).onFile(picked);

      final state = container.read(decryptProvider);
      expect(state.detected, DetectedFormat.ageBinary);
      expect(state.need, DecryptNeed.passphrase);
      expect(picked.mostRead, lessThanOrEqualTo(SizeLimits.message + 1));
    }
  });
}

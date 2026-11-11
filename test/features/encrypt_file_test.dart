import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/features/encrypt/encrypt_controller.dart';
import 'package:web_crypt/services/file_service.dart';

import '../support/harness.dart';

/// stands in for the browser download, keeping what it was handed
class _Downloads extends FileService {
  final saved = <String>[];

  @override
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    saved.add(suggestedName);
    return null;
  }
}

/// encrypts one in-memory file, as the web does, and hands back its job
Future<FileJob> _encryptNotes(String passphrase, _Downloads downloads) async {
  final container = ProviderContainer(
    overrides: [
      storageServiceProvider.overrideWithValue(await testStorage()),
      fileServiceProvider.overrideWithValue(downloads),
    ],
  );
  addTearDown(container.dispose);
  container.listen(encryptProvider, (_, _) {});
  final controller = container.read(encryptProvider.notifier)
    ..addFiles([
      PickedFile(
        name: 'notes.txt',
        size: 5,
        bytes: Uint8List.fromList(utf8.encode('hello')),
      ),
    ]);
  await controller.encryptFiles(passphrase: passphrase);
  return container.read(encryptProvider).files.single;
}

void main() {
  test('a finished file lets go of its contents', () async {
    final downloads = _Downloads();
    final job = await _encryptNotes('pw', downloads);
    expect(job.status, JobStatus.done);
    expect(downloads.saved, ['notes.txt.age']);
    expect(job.source.bytes, isNull);
    expect(job.source.name, 'notes.txt');
    expect(job.source.size, 5);
  });

  test('a failed file keeps its contents for another go', () async {
    final downloads = _Downloads();
    final job = await _encryptNotes('', downloads);
    expect(job.status, JobStatus.failed);
    expect(downloads.saved, isEmpty);
    expect(job.source.bytes, isNotNull);
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/crypto/crypto_jobs.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/runner/job_worker.dart';

const supportsFileJobs = true;

/// native runs every job in its own isolate, so nothing blocks the UI thread.
/// progress comes back over a port the isolate closure captures
Future<CryptoJobResult> runCryptoJob(
  CryptoJob job, {
  void Function(int processed)? onProgress,
}) async {
  if (onProgress == null) return _spawn(job);
  final port = ReceivePort();
  final subscription = port.listen((message) {
    if (message is int) onProgress(message);
  });
  try {
    return await _spawn(job, port.sendPort);
  } finally {
    await subscription.cancel();
    port.close();
  }
}

/// its own function, so the isolate does not copy onProgress across too
Future<CryptoJobResult> _spawn(CryptoJob job, [SendPort? progress]) =>
    Isolate.run(() => _execute(job, progress), debugName: 'crypto');

Future<CryptoJobResult> _execute(CryptoJob job, [SendPort? progress]) async {
  return switch (job) {
    EncryptBytesJob() ||
    DecryptBytesJob() ||
    GenerateKeyJob() => executeBytesJob(job),
    EncryptFileJob() => _encryptFile(job, progress),
    DecryptFileJob() => _decryptFile(job, progress),
  };
}

Future<CryptoJobResult> _encryptFile(
  EncryptFileJob job,
  SendPort? progress,
) async {
  await _pipeToFile(
    job.targetPath,
    (source) => formatFor(job.format).encrypt(source, job.options),
    _withProgress(File(job.sourcePath).openRead(), progress),
  );
  return CryptoJobResult(format: job.format);
}

Future<CryptoJobResult> _decryptFile(
  DecryptFileJob job,
  SendPort? progress,
) async {
  final headed = await peekHead(
    _withProgress(File(job.sourcePath).openRead(), progress),
    detectionHeadSize,
  );
  final kind = formatForInput(headed.head);

  var metadata = const DecryptMetadata();
  await _pipeToFile(
    job.targetPath,
    (source) => formatFor(kind).decrypt(
      source,
      DecryptOptions(
        passphrase: job.passphrase,
        identities: job.identities,
        verificationKeys: job.verificationKeys,
        onMetadata: (value) => metadata = value,
      ),
    ),
    headed.stream,
  );
  return CryptoJobResult(metadata: metadata, format: kind);
}

/// counts bytes read off the source, which is what a progress bar wants
Stream<List<int>> _withProgress(Stream<List<int>> source, SendPort? progress) {
  if (progress == null) return source;
  return countingBytes(source, progress.send);
}

/// opens the target only once there is output, so a wrong key leaves it alone
Future<void> _pipeToFile(
  String targetPath,
  Stream<List<int>> Function(Stream<List<int>>) transform,
  Stream<List<int>> source,
) async {
  // written in place, as macOS only lets the app write the path that was picked
  final target = File(targetPath);
  final output = StreamIterator(transform(source));
  // set only once opening works, so a file we could not open is never deleted
  RandomAccessFile? file;
  try {
    while (await output.moveNext()) {
      file ??= await target.open(mode: FileMode.write);
      await file.writeFrom(output.current);
    }
    file ??= await target.open(mode: FileMode.write);
    await file.close();
  } on Object catch (error) {
    await _quietly(output.cancel);
    // a half-written file would still look like a real one
    if (file != null) {
      await _quietly(file.close);
      await _quietly(target.delete);
    }
    if (error is AppException) rethrow;
    if (error is FileSystemException) throw const FileAccessFailed();
    throw const CryptoFailed();
  }
}

/// cleanup after a failure, which is the error worth reporting
Future<void> _quietly(Future<Object?> Function() step) async {
  try {
    await step();
  } on Object {
    // best effort
  }
}

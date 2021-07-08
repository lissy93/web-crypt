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
  if (onProgress == null) {
    return Isolate.run(() => _execute(job), debugName: 'crypto');
  }
  final port = ReceivePort();
  final subscription = port.listen((message) {
    if (message is int) onProgress(message);
  });
  final send = port.sendPort;
  try {
    return await Isolate.run(() => _execute(job, send), debugName: 'crypto');
  } finally {
    await subscription.cancel();
    port.close();
  }
}

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

/// any failure removes the target, because a half-written file still looks
/// like a real one
Future<void> _pipeToFile(
  String targetPath,
  Stream<List<int>> Function(Stream<List<int>>) transform,
  Stream<List<int>> source,
) async {
  final target = File(targetPath);
  final sink = target.openWrite();
  try {
    await sink.addStream(transform(source));
    await sink.flush();
    await sink.close();
  } on Object catch (error) {
    await _closeQuietly(sink);
    await _deleteQuietly(target);
    if (error is AppException) rethrow;
    if (error is FileSystemException) throw const FileAccessFailed();
    throw const CryptoFailed();
  }
}

Future<void> _closeQuietly(IOSink sink) async {
  try {
    await sink.close();
  } on Object {
    // the original failure is the one worth reporting
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } on FileSystemException {
    // nothing useful to do here
  }
}

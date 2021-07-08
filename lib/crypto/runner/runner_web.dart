import 'package:web_crypt/crypto/crypto_jobs.dart';
import 'package:web_crypt/crypto/runner/job_worker.dart';

const supportsFileJobs = false;

/// web has no isolates, so this runs in place. age yields between 64 KiB
/// chunks and stays responsive, PGP is one synchronous pass, which is why the
/// size limits matter here
Future<CryptoJobResult> runCryptoJob(
  CryptoJob job, {
  void Function(int processed)? onProgress,
}) async {
  // let the pressed state and spinner paint before the thread goes
  await Future<void>.delayed(Duration.zero);
  return executeBytesJob(job);
}

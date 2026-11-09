import 'package:web_crypt/crypto/crypto_jobs.dart';
import 'package:web_crypt/crypto/runner/job_worker.dart';

const supportsFileJobs = false;

Future<CryptoJobResult> runCryptoJob(
  CryptoJob job, {
  void Function(int processed)? onProgress,
}) => executeBytesJob(job);

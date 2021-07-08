import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/services/file_service.dart';

enum EncryptTab { message, file }

enum JobStatus { waiting, running, done, failed }

class FileJob {
  const FileJob({
    required this.source,
    this.status = JobStatus.waiting,
    this.outputName,
    this.outputPath,
    this.outputBytes,
    this.error,
    this.processed = 0,
  });

  final PickedFile source;
  final JobStatus status;

  /// bytes read off the source so far, zero until the job starts
  final int processed;
  final String? outputName;

  /// set on desktop once written, null on web where the browser downloads it
  final String? outputPath;
  final Uint8List? outputBytes;
  final Object? error;

  /// null when the size is unknown, which is how the UI picks between a bar
  /// and a spinner
  double? get fraction =>
      source.size > 0 ? (processed / source.size).clamp(0.0, 1.0) : null;

  FileJob copyWith({
    JobStatus? status,
    String? outputName,
    String? outputPath,
    Uint8List? outputBytes,
    Object? error,
    int? processed,
  }) {
    return FileJob(
      source: source,
      status: status ?? this.status,
      outputName: outputName ?? this.outputName,
      outputPath: outputPath ?? this.outputPath,
      outputBytes: outputBytes ?? this.outputBytes,
      error: error,
      processed: processed ?? this.processed,
    );
  }
}

class EncryptState {
  const EncryptState({
    this.tab = EncryptTab.message,
    this.format = CryptoFormatKind.age,
    this.mode = EncryptMode.passphrase,
    this.armor = false,
    this.recipients = const [],
    this.files = const [],
    this.busy = false,
    this.output,
    this.error,
  });

  final EncryptTab tab;
  final CryptoFormatKind format;
  final EncryptMode mode;
  final bool armor;
  final List<Recipient> recipients;
  final List<FileJob> files;
  final bool busy;
  final String? output;
  final Object? error;

  bool get hasOutput => output != null;

  List<Recipient> get recipientsForFormat =>
      recipients.where((r) => r.format == format).toList(growable: false);

  EncryptState copyWith({
    EncryptTab? tab,
    CryptoFormatKind? format,
    EncryptMode? mode,
    bool? armor,
    List<Recipient>? recipients,
    List<FileJob>? files,
    bool? busy,
    String? output,
    Object? error,
    bool clearOutput = false,
    bool clearError = true,
  }) {
    return EncryptState(
      tab: tab ?? this.tab,
      format: format ?? this.format,
      mode: mode ?? this.mode,
      armor: armor ?? this.armor,
      recipients: recipients ?? this.recipients,
      files: files ?? this.files,
      busy: busy ?? this.busy,
      output: clearOutput ? null : (output ?? this.output),
      error: clearError ? error : (error ?? this.error),
    );
  }
}

final encryptProvider = NotifierProvider<EncryptController, EncryptState>(
  EncryptController.new,
);

class EncryptController extends Notifier<EncryptState> {
  @override
  EncryptState build() {
    final storage = ref.read(storageServiceProvider);
    return EncryptState(
      format: storage.lastFormat,
      mode: storage.lastMode,
      armor: storage.lastArmor,
    );
  }

  CryptoService get _crypto => ref.read(cryptoServiceProvider);

  FileService get _files => ref.read(fileServiceProvider);

  void setTab(EncryptTab tab) =>
      state = state.copyWith(tab: tab, clearOutput: true);

  Future<void> setFormat(CryptoFormatKind format) async {
    state = state.copyWith(format: format, clearOutput: true);
    await ref.read(storageServiceProvider).setLastFormat(format);
  }

  Future<void> setMode(EncryptMode mode) async {
    state = state.copyWith(mode: mode, clearOutput: true);
    await ref.read(storageServiceProvider).setLastMode(mode);
  }

  Future<void> setArmor(bool armor) async {
    state = state.copyWith(armor: armor);
    await ref.read(storageServiceProvider).setLastArmor(armor);
  }

  void addRecipient(Recipient recipient) {
    if (state.recipients.contains(recipient)) return;
    state = state.copyWith(recipients: [...state.recipients, recipient]);
  }

  void removeRecipient(Recipient recipient) {
    state = state.copyWith(
      recipients: state.recipients.where((r) => r != recipient).toList(),
    );
  }

  void addFiles(List<PickedFile> files) {
    state = state.copyWith(
      files: [
        ...state.files,
        for (final file in files) FileJob(source: file),
      ],
    );
  }

  void removeFile(int index) {
    final files = [...state.files]..removeAt(index);
    state = state.copyWith(files: files);
  }

  void reset() =>
      state = state.copyWith(clearOutput: true, files: const [], busy: false);

  EncryptOptions _options({String? passphrase, String? filename}) {
    return EncryptOptions(
      mode: state.mode,
      passphrase: passphrase,
      recipients: state.recipientsForFormat,
      armor: state.armor,
      filename: filename,
    );
  }

  /// text output is always armored, whatever the file toggle says
  Future<void> encryptMessage(String message, {String? passphrase}) async {
    if (state.busy || message.isEmpty) return;
    final bytes = utf8.encode(message);
    if (bytes.length > SizeLimits.message) {
      state = state.copyWith(error: const InputTooLarge(SizeLimits.message));
      return;
    }

    state = state.copyWith(busy: true, clearOutput: true);
    try {
      final output = await _crypto.encryptBytes(
        format: state.format,
        input: bytes,
        options: EncryptOptions(
          mode: state.mode,
          passphrase: passphrase,
          recipients: state.recipientsForFormat,
          armor: true,
        ),
      );
      state = state.copyWith(busy: false, output: utf8.decode(output));
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
    } on Object {
      state = state.copyWith(busy: false, error: const CryptoFailed());
    }
  }

  Future<void> encryptFiles({String? passphrase}) async {
    if (state.busy || state.files.isEmpty) return;
    state = state.copyWith(busy: true);

    for (var i = 0; i < state.files.length; i++) {
      if (state.files[i].status == JobStatus.done) continue;
      _updateJob(
        i,
        (job) => job.copyWith(status: JobStatus.running, processed: 0),
      );
      try {
        await _encryptOne(i, passphrase: passphrase);
      } on AppException catch (error) {
        _updateJob(
          i,
          (job) => job.copyWith(status: JobStatus.failed, error: error),
        );
      } on Object {
        _updateJob(
          i,
          (job) => job.copyWith(
            status: JobStatus.failed,
            error: const CryptoFailed(),
          ),
        );
      }
    }
    state = state.copyWith(busy: false);
  }

  Future<void> _encryptOne(int index, {String? passphrase}) async {
    final job = state.files[index];
    final suffix = state.format == CryptoFormatKind.age ? '.age' : '.gpg';
    final outputName = '${job.source.name}$suffix';
    final options = _options(passphrase: passphrase, filename: job.source.name);

    if (_crypto.canStreamFiles && job.source.path != null) {
      final target = await _files.chooseSavePath(suggestedName: outputName);
      if (target == null) {
        _updateJob(index, (j) => j.copyWith(status: JobStatus.waiting));
        return;
      }
      await _crypto.encryptFile(
        format: state.format,
        sourcePath: job.source.path!,
        targetPath: target,
        options: options,
        onProgress: (processed) =>
            _updateJob(index, (j) => j.copyWith(processed: processed)),
      );
      _updateJob(
        index,
        (j) => j.copyWith(
          status: JobStatus.done,
          outputName: outputName,
          outputPath: target,
        ),
      );
      return;
    }

    final bytes = await _crypto.encryptBytes(
      format: state.format,
      input: await job.source.read(),
      options: options,
    );
    await _files.saveBytes(suggestedName: outputName, bytes: bytes);
    _updateJob(
      index,
      (j) => j.copyWith(
        status: JobStatus.done,
        outputName: outputName,
        outputBytes: bytes,
      ),
    );
  }

  Future<void> saveOutputAsFile(String suggestedName) async {
    final output = state.output;
    if (output == null) return;
    try {
      await _files.saveBytes(
        suggestedName: suggestedName,
        bytes: utf8.encode(output),
      );
    } on AppException catch (error) {
      state = state.copyWith(error: error);
    }
  }

  void _updateJob(int index, FileJob Function(FileJob) update) {
    final files = [...state.files];
    files[index] = update(files[index]);
    state = state.copyWith(files: files);
  }
}

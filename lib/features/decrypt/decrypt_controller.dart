import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/crypto/age/age_format.dart';
import 'package:web_crypt/crypto/crypto_service.dart';
import 'package:web_crypt/crypto/detector.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/pgp/pgp_format.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/services/file_service.dart';

/// what the input still needs before it can be opened
enum DecryptNeed {
  nothing,
  passphrase,
  identity,

  /// a key that could open this is here, but locked with its own passphrase
  keyPassphrase,
}

class DecryptState {
  const DecryptState({
    this.detected = DetectedFormat.unknown,
    this.source,
    this.pastedLength = 0,
    this.need = DecryptNeed.nothing,
    this.busy = false,
    this.outputText,
    this.outputBytes,
    this.savedAs,
    this.metadata = const DecryptMetadata(),
    this.error,
    this.triedSilently = false,
    this.extraIdentities = const [],
  });

  final DetectedFormat detected;

  /// set when the input came from a file rather than the text box
  final PickedFile? source;
  final int pastedLength;
  final DecryptNeed need;
  final bool busy;

  /// only set when the plaintext is valid UTF-8 and small enough to show
  final String? outputText;
  final Uint8List? outputBytes;
  final String? savedAs;
  final DecryptMetadata metadata;
  final Object? error;

  /// true once unlocked keyring keys have been tried without asking
  final bool triedSilently;

  /// pasted or picked here rather than saved, and live only as long as this
  /// screen does
  final List<Identity> extraIdentities;

  bool get hasInput => source != null || pastedLength > 0;

  bool get hasOutput => outputText != null || outputBytes != null;

  bool get isReady => hasInput && detected.isMessage;

  DecryptState copyWith({
    DetectedFormat? detected,
    PickedFile? source,
    int? pastedLength,
    DecryptNeed? need,
    bool? busy,
    String? outputText,
    Uint8List? outputBytes,
    String? savedAs,
    DecryptMetadata? metadata,
    Object? error,
    bool? triedSilently,
    List<Identity>? extraIdentities,
    bool clearSource = false,
    bool clearOutput = false,
  }) {
    return DecryptState(
      detected: detected ?? this.detected,
      source: clearSource ? null : (source ?? this.source),
      pastedLength: pastedLength ?? this.pastedLength,
      need: need ?? this.need,
      busy: busy ?? this.busy,
      outputText: clearOutput ? null : (outputText ?? this.outputText),
      outputBytes: clearOutput ? null : (outputBytes ?? this.outputBytes),
      savedAs: clearOutput ? null : (savedAs ?? this.savedAs),
      metadata: metadata ?? this.metadata,
      error: error,
      triedSilently: triedSilently ?? this.triedSilently,
      extraIdentities: extraIdentities ?? this.extraIdentities,
    );
  }
}

/// auto-disposed on purpose: the decrypted plaintext and any ad-hoc private
/// key live in this state, and neither should outlive the screen
final decryptProvider = NotifierProvider<DecryptController, DecryptState>(
  DecryptController.new,
  isAutoDispose: true,
);

class DecryptController extends Notifier<DecryptState> {
  @override
  DecryptState build() => const DecryptState();

  CryptoService get _crypto => ref.read(cryptoServiceProvider);

  FileService get _files => ref.read(fileServiceProvider);

  /// detection runs the moment something arrives, before anything is asked for
  void onTextChanged(String text) {
    if (state.busy) return;
    if (text.trim().isEmpty) {
      state = const DecryptState();
      return;
    }
    final bytes = utf8.encode(text);
    final detected = FormatDetector.detect(bytes);
    state = DecryptState(
      detected: detected,
      pastedLength: text.length,
      need: _needFor(detected, bytes, whole: bytes),
    );
  }

  Future<void> onFile(PickedFile file) async {
    if (state.busy) return;
    state = const DecryptState(busy: true);
    try {
      // read at most 1 MB, and only look inside if that was the whole file
      final start = await file.readHead(SizeLimits.message + 1);
      final whole = start.length <= SizeLimits.message ? start : null;
      final detected = FormatDetector.detect(start);
      state = DecryptState(
        detected: detected,
        source: file,
        need: _needFor(detected, start, whole: whole),
      );
    } on AppException catch (error) {
      state = DecryptState(error: error);
    } on Object {
      state = const DecryptState(error: FileAccessFailed());
    }
  }

  /// [whole] is the complete input where it is available, which allows a look
  /// inside an armored container instead of a guess
  DecryptNeed _needFor(
    DetectedFormat detected,
    List<int> head, {
    Uint8List? whole,
  }) {
    if (!detected.isMessage) return DecryptNeed.nothing;
    if (detected.formatKind == CryptoFormatKind.age) {
      // binary shows its stanzas in the head, armored has to be unwrapped
      final header = detected == DetectedFormat.ageArmored
          ? (whole == null ? null : AgeFormat.peekHeader(whole))
          : AgeHeaderPeek.read(head);
      if (header != null) {
        return header.needsPassphrase
            ? DecryptNeed.passphrase
            : DecryptNeed.identity;
      }
    }
    if (whole != null && detected.formatKind == CryptoFormatKind.pgp) {
      final peek = PgpFormat.peek(whole);
      if (peek != null) {
        if (peek.needsKey) return DecryptNeed.identity;
        if (peek.needsPassphrase) return DecryptNeed.passphrase;
      }
    }
    // nothing readable up front, so try the keys already held
    return DecryptNeed.nothing;
  }

  void clear() => state = const DecryptState();

  /// a private key pasted or picked on this screen, and saved nowhere
  void addIdentity(Identity identity) {
    state = state.copyWith(
      extraIdentities: [...state.extraIdentities, identity],
      need: DecryptNeed.nothing,
    );
  }

  /// tries unlocked keyring keys without asking. only if that fails does the
  /// UI prompt for a passphrase or a key
  Future<void> decrypt({
    String? passphrase,
    String? keyPassphrase,
    String? text,
  }) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearOutput: true);

    final keyring = ref.read(keyringProvider);
    final identities = [
      for (final identity in [
        ...keyring.availableIdentities,
        ...state.extraIdentities,
      ])
        // this guards the key itself, not the message
        if (keyPassphrase != null && keyPassphrase.isNotEmpty)
          Identity(
            format: identity.format,
            material: identity.material,
            passphrase: keyPassphrase,
            label: identity.label,
          )
        else
          identity,
    ];
    final verificationKeys = [for (final key in keyring.keys) key.asRecipient];

    try {
      if (_crypto.canStreamFiles && state.source?.path != null) {
        await _decryptToDisk(
          passphrase: passphrase,
          identities: identities,
          verificationKeys: verificationKeys,
        );
        return;
      }

      final input = state.source != null
          ? await state.source!.read()
          : utf8.encode(text ?? '');
      final outcome = await _crypto.decryptBytes(
        input: input,
        passphrase: passphrase,
        identities: identities,
        verificationKeys: verificationKeys,
      );
      _publishBytes(outcome.bytes, outcome.metadata);
    } on AppException catch (error) {
      _publishFailure(
        error,
        asked: passphrase != null || keyPassphrase != null,
      );
    } on Object {
      _publishFailure(
        const CryptoFailed(),
        asked: passphrase != null || keyPassphrase != null,
      );
    }
  }

  Future<void> _decryptToDisk({
    required String? passphrase,
    required List<Identity> identities,
    required List<Recipient> verificationKeys,
  }) async {
    final source = state.source!;
    final suggested = _strippedName(source.name);
    final target = await _files.chooseSavePath(suggestedName: suggested);
    if (target == null) {
      state = state.copyWith(busy: false);
      return;
    }
    final metadata = await _crypto.decryptFile(
      sourcePath: source.path!,
      targetPath: target,
      passphrase: passphrase,
      identities: identities,
      verificationKeys: verificationKeys,
    );
    state = state.copyWith(
      busy: false,
      savedAs: target,
      metadata: metadata,
      need: DecryptNeed.nothing,
    );
  }

  void _publishBytes(Uint8List bytes, DecryptMetadata metadata) {
    final text = _asDisplayableText(bytes);
    state = state.copyWith(
      busy: false,
      outputText: text,
      outputBytes: text == null ? bytes : null,
      metadata: metadata,
      need: DecryptNeed.nothing,
    );
  }

  void _publishFailure(AppException error, {required bool asked}) {
    final need = switch (error) {
      WrongPassphrase() =>
        state.need == DecryptNeed.keyPassphrase
            ? DecryptNeed.keyPassphrase
            : DecryptNeed.passphrase,
      KeyLocked() => DecryptNeed.keyPassphrase,
      NoMatchingKey() => DecryptNeed.identity,
      _ => state.need,
    };
    // failing on keys nobody chose is not worth reporting
    final quiet =
        !asked &&
        !state.triedSilently &&
        (error is WrongPassphrase || error is NoMatchingKey);
    state = state.copyWith(
      busy: false,
      need: need,
      triedSilently: true,
      error: quiet ? null : error,
    );
  }

  Future<void> saveOutputAsFile() async {
    final bytes =
        state.outputBytes ??
        (state.outputText == null ? null : utf8.encode(state.outputText!));
    if (bytes == null) return;
    final suggested =
        state.metadata.filename ??
        (state.source == null
            ? 'message.txt'
            : _strippedName(state.source!.name));
    try {
      final saved = await _files.saveBytes(
        suggestedName: suggested,
        bytes: bytes,
      );
      state = state.copyWith(savedAs: saved ?? suggested);
    } on AppException catch (error) {
      state = state.copyWith(error: error);
    }
  }

  /// `report.pdf.age` becomes `report.pdf`
  static String _strippedName(String name) {
    for (final suffix in const ['.age', '.gpg', '.pgp', '.asc']) {
      if (name.toLowerCase().endsWith(suffix)) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return '$name.decrypted';
  }

  /// text output only when it really is text, so a decrypted image never
  /// floods the pane with control characters
  static String? _asDisplayableText(Uint8List bytes) {
    if (bytes.length > SizeLimits.message) return null;
    try {
      final text = utf8.decode(bytes);
      final hasControlBytes = text.codeUnits.any(
        (c) => c < 0x20 && c != 0x09 && c != 0x0a && c != 0x0d,
      );
      return hasControlBytes ? null : text;
    } on FormatException {
      return null;
    }
  }
}

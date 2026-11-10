import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/router.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/app_card.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/core/widgets/output_pane.dart';
import 'package:web_crypt/core/widgets/passphrase_field.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/features/decrypt/decrypt_controller.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/keys/widgets/keyring_dialogs.dart';
import 'package:web_crypt/features/shared/screen_scaffold.dart';
import 'package:web_crypt/services/file_service.dart';

class DecryptScreen extends ConsumerStatefulWidget {
  const DecryptScreen({super.key});

  @override
  ConsumerState<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends ConsumerState<DecryptScreen> {
  final _input = TextEditingController();
  final _passphrase = TextEditingController();
  final _keyPassphrase = TextEditingController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeOpenedFile());
  }

  /// a file the OS opened the app with goes in as if it was dropped here
  void _takeOpenedFile() {
    if (!mounted || ref.read(decryptProvider).busy) return;
    final file = ref.read(openedFileProvider.notifier).take();
    if (file == null) return;
    _input.clear();
    ref.read(decryptProvider.notifier).onFile(file);
  }

  @override
  void dispose() {
    _input.clear();
    _passphrase.clear();
    _keyPassphrase.clear();
    _input.dispose();
    _passphrase.dispose();
    _keyPassphrase.dispose();
    super.dispose();
  }

  Future<void> _decrypt() async {
    await ref
        .read(decryptProvider.notifier)
        .decrypt(
          passphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
          keyPassphrase: _keyPassphrase.text.isEmpty
              ? null
              : _keyPassphrase.text,
          text: _input.text,
        );
  }

  void _startOver() {
    _input.clear();
    _passphrase.clear();
    _keyPassphrase.clear();
    ref.read(decryptProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(openedFileProvider, (_, file) {
      if (file != null) _takeOpenedFile();
    });
    // one opened mid-load waits for that to finish
    ref.listen(decryptProvider.select((s) => s.busy), (_, busy) {
      if (!busy) _takeOpenedFile();
    });
    final state = ref.watch(decryptProvider);
    final controller = ref.read(decryptProvider.notifier);
    // held keys are tried on the first Decrypt, so only ask after that
    final nothingToTry =
        ref.watch(keyringProvider).availableIdentities.isEmpty &&
        state.extraIdentities.isEmpty;

    return ScreenScaffold(
      title: 'Decrypt',
      subtitle:
          'Paste an encrypted message or drop a file. We work out the rest.',
      children: [
        if (state.hasOutput || state.savedAs != null)
          _Result(state: state, onStartOver: _startOver)
        else ...[
          FileDropTarget(
            onDragChanged: (value) => setState(() => _dragging = value),
            onFiles: (files) {
              _input.clear();
              controller.onFile(files.first);
            },
            child: _InputArea(
              controller: _input,
              dragging: _dragging,
              state: state,
              onChanged: controller.onTextChanged,
              onBrowse: () async {
                final files = await ref
                    .read(fileServiceProvider)
                    .pickFiles(allowMultiple: false);
                if (files.isNotEmpty) {
                  _input.clear();
                  await controller.onFile(files.first);
                }
              },
              onClear: _startOver,
            ),
          ),
          if (state.hasInput) ...[
            const SizedBox(height: Space.lg),
            _DetectionBanner(state: state),
          ],
          if (state.need == DecryptNeed.passphrase) ...[
            const SizedBox(height: Space.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel(
                    'Passphrase',
                    hint: 'The one used when this was encrypted.',
                  ),
                  PassphraseField(
                    controller: _passphrase,
                    label: 'Passphrase',
                    autofocus: true,
                    onSubmitted: _decrypt,
                  ),
                ],
              ),
            ),
          ],
          if (state.need == DecryptNeed.identity &&
              (state.triedSilently || nothingToTry)) ...[
            const SizedBox(height: Space.lg),
            const _KeyPrompt(),
          ],
          if (state.need == DecryptNeed.keyPassphrase) ...[
            const SizedBox(height: Space.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel(
                    'Key passphrase',
                    hint:
                        'A key that can open this is protected by its own '
                        'passphrase.',
                  ),
                  PassphraseField(
                    controller: _keyPassphrase,
                    label: 'Key passphrase',
                    autofocus: true,
                    onSubmitted: _decrypt,
                  ),
                ],
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: Space.lg),
            InlineMessage.forError(state.error!),
          ],
          if (state.isReady) ...[
            const SizedBox(height: Space.lg),
            AppButton(
              label: 'Decrypt',
              kind: AppButtonKind.primary,
              icon: Icons.lock_open_outlined,
              busy: state.busy,
              expand: true,
              onPressed: _decrypt,
            ),
          ],
        ],
      ],
    );
  }
}

class _InputArea extends StatelessWidget {
  const _InputArea({
    required this.controller,
    required this.dragging,
    required this.state,
    required this.onChanged,
    required this.onBrowse,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool dragging;
  final DecryptState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onBrowse;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);

    if (state.source != null) {
      return AppCard(
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 20,
              color: colors.textMuted,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.source!.name, style: theme.textTheme.labelMedium),
                  Text(
                    formatBytes(state.source!.size),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.close,
              tooltip: 'Remove ${state.source!.name}',
              onPressed: onClear,
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: context.motion(Motion.fast),
      decoration: BoxDecoration(
        border: Border.all(
          color: dragging ? colors.accent : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(Radii.medium + 2),
      ),
      padding: const EdgeInsets.all(2),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Encrypted input'),
            TextField(
              controller: controller,
              onChanged: onChanged,
              minLines: 6,
              maxLines: 14,
              autofocus: true,
              style: monoStyle(context),
              decoration: const InputDecoration(
                hintText:
                    'Paste an encrypted message, or drop a file anywhere here',
              ),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              alignment: WrapAlignment.spaceBetween,
              children: [
                AppButton(
                  label: 'Choose a file',
                  icon: Icons.folder_open_outlined,
                  onPressed: onBrowse,
                ),
                if (controller.text.isNotEmpty)
                  AppButton(
                    label: 'Clear',
                    kind: AppButtonKind.quiet,
                    onPressed: onClear,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({required this.state});

  final DecryptState state;

  @override
  Widget build(BuildContext context) {
    if (!state.detected.isMessage) {
      if (state.detected.isKey) {
        return InlineMessage(
          title: 'That is a ${state.detected.describe}, not a message.',
          hint: 'Add it on the Keys screen, then come back here.',
          tone: MessageTone.info,
          action: Builder(
            builder: (context) => AppButton(
              label: 'Go to Keys',
              onPressed: () => context.go(Routes.keys),
            ),
          ),
        );
      }
      return const InlineMessage(
        title: "This doesn't look like an encrypted file or message.",
        hint:
            'web-crypt reads age and PGP. Check you copied the whole thing, '
            'header lines included.',
        tone: MessageTone.info,
      );
    }

    return InlineMessage(
      title: 'Found: ${state.detected.describe}.',
      hint: switch (state.need) {
        DecryptNeed.passphrase => 'It needs the passphrase it was locked with.',
        DecryptNeed.identity => 'It needs a private key.',
        DecryptNeed.keyPassphrase => 'It needs a key you have, unlocked.',
        DecryptNeed.nothing => 'Ready when you are.',
      },
      tone: MessageTone.info,
    );
  }
}

/// shown once the held keys have been tried and failed, or when there were
/// none to try
class _KeyPrompt extends ConsumerStatefulWidget {
  const _KeyPrompt();

  @override
  ConsumerState<_KeyPrompt> createState() => _KeyPromptState();
}

class _KeyPromptState extends ConsumerState<_KeyPrompt> {
  final _paste = TextEditingController();
  bool _pasting = false;
  Object? _error;

  @override
  void dispose() {
    _paste.clear();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _useMaterial(String material) async {
    setState(() => _error = null);
    try {
      final parsed = await parseKeyMaterial(
        material,
        id: 'ad-hoc',
        now: DateTime.now(),
      );
      if (!parsed.isPrivate) {
        setState(() => _error = const InvalidKeyMaterial());
        return;
      }
      ref
          .read(decryptProvider.notifier)
          .addIdentity(
            Identity(
              format: parsed.entry.format,
              material: parsed.privateMaterial!,
              label: parsed.entry.displayName,
            ),
          );
      _paste.clear();
      setState(() => _pasting = false);
    } on AppException catch (error) {
      setState(() => _error = error);
    }
  }

  Future<void> _fromFile() async {
    try {
      final files = await ref
          .read(fileServiceProvider)
          .pickFiles(allowMultiple: false);
      if (files.isEmpty) return;
      final bytes = await files.first.read();
      await _useMaterial(utf8.decode(bytes, allowMalformed: true));
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyring = ref.watch(keyringProvider);
    final state = ref.watch(decryptProvider);
    final theme = Theme.of(context);
    final tried = [...keyring.availableIdentities, ...state.extraIdentities];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Private key needed',
            hint: tried.isEmpty
                ? 'You have no private keys yet.'
                : state.triedSilently
                ? 'None of the keys you have could open this.'
                : 'Your keys will be tried when you press Decrypt.',
          ),
          if (keyring.isLocked) ...[
            InlineMessage(
              title: 'Your keyring is locked.',
              hint:
                  'Unlock it and your private keys will be tried '
                  'automatically.',
              tone: MessageTone.warning,
              action: AppButton(
                label: 'Unlock',
                icon: Icons.lock_open_outlined,
                onPressed: () => unlockKeyring(context),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
          if (tried.isNotEmpty) ...[
            for (final identity in tried)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  children: [
                    Icon(
                      identity.format == CryptoFormatKind.age
                          ? Icons.vpn_key_outlined
                          : Icons.key_outlined,
                      size: 16,
                      color: context.colors.textMuted,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        identity.label.isEmpty ? 'unnamed key' : identity.label,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.md),
          ],
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              AppButton(
                label: _pasting ? 'Cancel paste' : 'Paste a private key',
                icon: _pasting ? Icons.close : Icons.content_paste_outlined,
                onPressed: () => setState(() {
                  _pasting = !_pasting;
                  _error = null;
                }),
              ),
              AppButton(
                label: 'From file',
                icon: Icons.folder_open_outlined,
                onPressed: _fromFile,
              ),
              AppButton(
                label: 'Manage keys',
                kind: AppButtonKind.quiet,
                onPressed: () => context.go(Routes.keys),
              ),
            ],
          ),
          if (_pasting) ...[
            const SizedBox(height: Space.md),
            TextField(
              controller: _paste,
              minLines: 3,
              maxLines: 6,
              autofocus: true,
              style: monoStyle(context),
              decoration: const InputDecoration(
                hintText: 'AGE-SECRET-KEY-1… or an armored PGP private key',
              ),
            ),
            const SizedBox(height: Space.sm),
            AppButton(
              label: 'Use this key',
              kind: AppButtonKind.secondary,
              onPressed: () => _useMaterial(_paste.text),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            InlineMessage.forError(_error!),
          ],
        ],
      ),
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result({required this.state, required this.onStartOver});

  final DecryptState state;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(decryptProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.metadata.signatures.isNotEmpty) ...[
          _Signatures(signatures: state.metadata.signatures),
          const SizedBox(height: Space.lg),
        ],
        AppCard(
          child: state.outputText != null
              ? OutputPane(
                  title: 'Decrypted',
                  value: state.outputText!,
                  sensitive: true,
                  footnote: state.metadata.filename == null
                      ? null
                      : 'Original name: ${state.metadata.filename}',
                  onStartOver: onStartOver,
                  onSave: controller.saveOutputAsFile,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: context.colors.success,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            'Decrypted',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: context.colors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      state.savedAs != null
                          ? 'Saved to ${state.savedAs}'
                          : 'This is not text, so save it as a file.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.lg),
                    Row(
                      children: [
                        if (state.savedAs == null)
                          AppButton(
                            label: 'Save as file',
                            icon: Icons.download_outlined,
                            kind: AppButtonKind.primary,
                            onPressed: controller.saveOutputAsFile,
                          ),
                        const SizedBox(width: Space.sm),
                        AppButton(
                          label: 'Start over',
                          kind: AppButtonKind.quiet,
                          onPressed: onStartOver,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Signatures extends StatelessWidget {
  const _Signatures({required this.signatures});

  final List<SignatureInfo> signatures;

  @override
  Widget build(BuildContext context) {
    final first = signatures.first;
    return InlineMessage(
      title: switch (first.verdict) {
        SignatureVerdict.valid => 'Signature checks out.',
        SignatureVerdict.invalid => 'The signature did not check out.',
        SignatureVerdict.unknownSigner =>
          'Signed, but by a key you do not have.',
      },
      hint: 'Signer key ID ${groupFingerprint(first.keyId)}',
      tone: switch (first.verdict) {
        SignatureVerdict.valid => MessageTone.success,
        SignatureVerdict.invalid => MessageTone.error,
        SignatureVerdict.unknownSigner => MessageTone.info,
      },
    );
  }
}

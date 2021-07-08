import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/utils/passphrase_strength.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/app_card.dart';
import 'package:web_crypt/core/widgets/drop_zone.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/core/widgets/output_pane.dart';
import 'package:web_crypt/core/widgets/passphrase_field.dart';
import 'package:web_crypt/core/widgets/segmented.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/features/encrypt/encrypt_controller.dart';
import 'package:web_crypt/features/encrypt/widgets/recipient_picker.dart';
import 'package:web_crypt/features/shared/screen_scaffold.dart';

class EncryptScreen extends ConsumerStatefulWidget {
  const EncryptScreen({super.key});

  @override
  ConsumerState<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends ConsumerState<EncryptScreen> {
  final _message = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  String? _passphraseError;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(_onPassphraseChanged);
    _confirm.addListener(_onPassphraseChanged);
  }

  @override
  void dispose() {
    // listeners go first, since clearing fires them
    _passphrase.removeListener(_onPassphraseChanged);
    _confirm.removeListener(_onPassphraseChanged);
    // secrets live no longer than they must
    _message.clear();
    _passphrase.clear();
    _confirm.clear();
    _message.dispose();
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onPassphraseChanged() {
    if (!mounted) return;
    setState(() => _passphraseError = null);
  }

  String? _validatePassphrase(EncryptState state) {
    if (state.mode != EncryptMode.passphrase) return null;
    if (_passphrase.text.isEmpty) return 'Enter a passphrase.';
    if (_passphrase.text != _confirm.text) return 'The two do not match.';
    return null;
  }

  Future<void> _encryptMessage() async {
    final state = ref.read(encryptProvider);
    final problem = _validatePassphrase(state);
    if (problem != null) {
      setState(() => _passphraseError = problem);
      return;
    }
    await ref
        .read(encryptProvider.notifier)
        .encryptMessage(_message.text, passphrase: _passphrase.text);
  }

  Future<void> _encryptFiles() async {
    final state = ref.read(encryptProvider);
    final problem = _validatePassphrase(state);
    if (problem != null) {
      setState(() => _passphraseError = problem);
      return;
    }
    await ref
        .read(encryptProvider.notifier)
        .encryptFiles(passphrase: _passphrase.text);
  }

  void _startOver() {
    _message.clear();
    _passphrase.clear();
    _confirm.clear();
    setState(() => _passphraseError = null);
    ref.read(encryptProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(encryptProvider);
    final controller = ref.read(encryptProvider.notifier);

    return ScreenScaffold(
      title: 'Encrypt',
      subtitle:
          'Scramble a message or a file so only the right person can read it.',
      children: [
        AppSegmented<EncryptTab>(
          label: 'What to encrypt',
          value: state.tab,
          onChanged: controller.setTab,
          options: const [
            SegmentedOption(
              value: EncryptTab.message,
              label: 'Message',
              icon: Icons.notes_outlined,
            ),
            SegmentedOption(
              value: EncryptTab.file,
              label: 'File',
              icon: Icons.insert_drive_file_outlined,
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        if (state.tab == EncryptTab.message)
          _MessageTab(
            state: state,
            controller: _message,
            onEncrypt: _encryptMessage,
            onStartOver: _startOver,
            passphraseFields: _passphrasePanel(state),
          )
        else
          _FileTab(
            state: state,
            onEncrypt: _encryptFiles,
            onStartOver: _startOver,
            passphraseFields: _passphrasePanel(state),
          ),
      ],
    );
  }

  Widget _passphrasePanel(EncryptState state) {
    final controller = ref.read(encryptProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ControlPair(
          first: _LabelledControl(
            label: 'Format',
            child: AppSegmented<CryptoFormatKind>(
              label: 'Encryption format',
              value: state.format,
              onChanged: controller.setFormat,
              options: const [
                SegmentedOption(value: CryptoFormatKind.age, label: 'age'),
                SegmentedOption(value: CryptoFormatKind.pgp, label: 'PGP'),
              ],
            ),
          ),
          second: _LabelledControl(
            label: 'Lock it with',
            child: AppSegmented<EncryptMode>(
              label: 'Encryption mode',
              value: state.mode,
              onChanged: controller.setMode,
              options: const [
                SegmentedOption(
                  value: EncryptMode.passphrase,
                  label: 'Passphrase',
                ),
                SegmentedOption(
                  value: EncryptMode.recipients,
                  label: 'Recipients',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        if (state.mode == EncryptMode.passphrase)
          _PassphrasePair(
            passphrase: _passphrase,
            confirm: _confirm,
            error: _passphraseError,
            onSubmit: state.tab == EncryptTab.message
                ? _encryptMessage
                : _encryptFiles,
          )
        else
          RecipientPicker(
            format: state.format,
            selected: state.recipientsForFormat,
            onAdd: controller.addRecipient,
            onRemove: controller.removeRecipient,
          ),
      ],
    );
  }
}

/// side by side when there is room, stacked when there is not
class _ControlPair extends StatelessWidget {
  const _ControlPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  static const _sideBySideFrom = 520.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideFrom) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              first,
              const SizedBox(height: Space.lg),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: Space.lg),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _LabelledControl extends StatelessWidget {
  const _LabelledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Space.sm),
        Align(alignment: Alignment.centerLeft, child: child),
      ],
    );
  }
}

class _PassphrasePair extends StatelessWidget {
  const _PassphrasePair({
    required this.passphrase,
    required this.confirm,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController passphrase;
  final TextEditingController confirm;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final score = scorePassphrase(passphrase.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PassphraseField(
          controller: passphrase,
          label: 'Passphrase',
          hint: 'Four or more unrelated words works well',
        ),
        PassphraseStrengthBar(passphrase: passphrase.text),
        const SizedBox(height: Space.md),
        PassphraseField(
          controller: confirm,
          label: 'Passphrase again',
          errorText: error,
          onSubmitted: onSubmit,
        ),
        if (passphrase.text.isNotEmpty &&
            score.level == PassphraseLevel.weak) ...[
          const SizedBox(height: Space.md),
          const InlineMessage(
            title: 'That passphrase is easy to guess.',
            hint:
                'You can carry on, but a longer one protects this much better.',
            tone: MessageTone.warning,
          ),
        ],
      ],
    );
  }
}

class _MessageTab extends ConsumerWidget {
  const _MessageTab({
    required this.state,
    required this.controller,
    required this.onEncrypt,
    required this.onStartOver,
    required this.passphraseFields,
  });

  final EncryptState state;
  final TextEditingController controller;
  final VoidCallback onEncrypt;
  final VoidCallback onStartOver;
  final Widget passphraseFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.hasOutput) {
      return AppCard(
        child: OutputPane(
          title: 'Encrypted',
          value: state.output!,
          sensitive: false,
          footnote: 'Send this whole block, header lines included.',
          onStartOver: onStartOver,
          onSave: () => ref
              .read(encryptProvider.notifier)
              .saveOutputAsFile(
                state.format == CryptoFormatKind.age
                    ? 'message.age'
                    : 'message.asc',
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Your message'),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 12,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type or paste your message',
                ),
              ),
              const SizedBox(height: Space.xl),
              passphraseFields,
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: Space.lg),
          InlineMessage.forError(state.error!),
        ],
        const SizedBox(height: Space.lg),
        AppButton(
          label: 'Encrypt',
          kind: AppButtonKind.primary,
          icon: Icons.lock_outline,
          busy: state.busy,
          expand: true,
          onPressed: onEncrypt,
        ),
      ],
    );
  }
}

class _FileTab extends ConsumerWidget {
  const _FileTab({
    required this.state,
    required this.onEncrypt,
    required this.onStartOver,
    required this.passphraseFields,
  });

  final EncryptState state;
  final VoidCallback onEncrypt;
  final VoidCallback onStartOver;
  final Widget passphraseFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(encryptProvider.notifier);
    final crypto = ref.read(cryptoServiceProvider);
    final warnAt = crypto.warnInputBytes;
    final oversized =
        warnAt != null && state.files.any((job) => job.source.size > warnAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropZone(
          title: 'Drop files here, or browse',
          subtitle: 'Each one is encrypted on its own',
          onFiles: controller.addFiles,
          compact: state.files.isNotEmpty,
          enabled: !state.busy,
        ),
        if (state.files.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                for (var i = 0; i < state.files.length; i++)
                  _FileRow(
                    job: state.files[i],
                    onRemove: state.busy
                        ? null
                        : () => controller.removeFile(i),
                  ),
              ],
            ),
          ),
        ],
        if (oversized) ...[
          const SizedBox(height: Space.lg),
          InlineMessage(
            title: 'That is a big file for a browser tab.',
            hint:
                'Anything over ${formatBytes(warnAt)} will be slow here. '
                'The desktop app streams instead.',
            tone: MessageTone.warning,
          ),
        ],
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              passphraseFields,
              const SizedBox(height: Space.xl),
              _ArmorToggle(value: state.armor, onChanged: controller.setArmor),
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: Space.lg),
          InlineMessage.forError(state.error!),
        ],
        const SizedBox(height: Space.lg),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: state.files.length > 1
                    ? 'Encrypt ${state.files.length} files'
                    : 'Encrypt',
                kind: AppButtonKind.primary,
                icon: Icons.lock_outline,
                busy: state.busy,
                expand: true,
                onPressed: state.files.isEmpty ? null : onEncrypt,
              ),
            ),
            if (state.files.isNotEmpty) ...[
              const SizedBox(width: Space.sm),
              AppButton(
                label: 'Start over',
                kind: AppButtonKind.quiet,
                onPressed: state.busy ? null : onStartOver,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ArmorToggle extends StatelessWidget {
  const _ArmorToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Text-safe output', style: theme.textTheme.titleSmall),
                const SizedBox(height: Space.xs),
                Text(
                  'Larger, but survives being pasted into email or chat.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.lg),
          SizedBox(
            height: Layout.minTapTarget,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.job, required this.onRemove});

  final FileJob job;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          _StatusIcon(status: job.status),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.outputName ?? job.source.name,
                  style: theme.textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  switch (job.status) {
                    JobStatus.waiting => formatBytes(job.source.size),
                    JobStatus.running =>
                      job.fraction == null
                          ? 'Working…'
                          : '${formatBytes(job.processed)} of '
                                '${formatBytes(job.source.size)}',
                    JobStatus.done =>
                      job.outputPath != null ? 'Saved' : 'Downloaded',
                    JobStatus.failed => 'Failed',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: job.status == JobStatus.failed
                        ? colors.danger
                        : colors.textMuted,
                  ),
                ),
                if (job.status == JobStatus.running) ...[
                  const SizedBox(height: Space.sm),
                  Semantics(
                    label: job.fraction == null
                        ? 'Working on ${job.source.name}'
                        : '${(job.fraction! * 100).round()} percent of '
                              '${job.source.name}',
                    child: ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: job.fraction),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null && job.status != JobStatus.running)
            AppIconButton(
              icon: Icons.close,
              tooltip: 'Remove ${job.source.name}',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 20,
      height: 20,
      child: switch (status) {
        JobStatus.waiting => Icon(
          Icons.insert_drive_file_outlined,
          size: 18,
          color: colors.textMuted,
        ),
        JobStatus.running => const CircularProgressIndicator(strokeWidth: 2),
        JobStatus.done => Icon(
          Icons.check_circle_outline,
          size: 18,
          color: colors.success,
        ),
        JobStatus.failed => Icon(
          Icons.error_outline,
          size: 18,
          color: colors.danger,
        ),
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/core/widgets/passphrase_field.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';

/// asks how private keys should be kept, and returns true if the caller may
/// go ahead
Future<bool> chooseKeyringMode(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const _KeyringSetupDialog(),
  );
  return result ?? false;
}

class _KeyringSetupDialog extends ConsumerStatefulWidget {
  const _KeyringSetupDialog();

  @override
  ConsumerState<_KeyringSetupDialog> createState() => _KeyringSetupState();
}

class _KeyringSetupState extends ConsumerState<_KeyringSetupDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _persist = true;
  bool _remember = false;
  bool _busy = false;
  Object? _error;
  String? _fieldError;

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(keyringProvider.notifier);
    if (!_persist) {
      try {
        await controller.chooseSessionOnly();
      } on Object catch (error) {
        if (mounted) setState(() => _error = error);
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _fieldError = 'Choose a master password.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _fieldError = 'The two do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await controller.chooseMasterPassword(
        _password.text,
        remember: _remember,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRemember = ref
        .read(storageServiceProvider)
        .canRememberMasterPassword;
    return AlertDialog(
      title: const Text('Where should this private key live?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Choice(
              selected: _persist,
              title: 'Keep it, locked with a master password',
              subtitle:
                  'Stored as a standard age file on this device. '
                  'You type the password once per session.',
              onTap: () => setState(() => _persist = true),
            ),
            const SizedBox(height: Space.sm),
            _Choice(
              selected: !_persist,
              title: 'This session only',
              subtitle:
                  'Nothing is written down. The key is gone when you '
                  'close web-crypt.',
              onTap: () => setState(() => _persist = false),
            ),
            if (_persist) ...[
              const SizedBox(height: Space.lg),
              PassphraseField(
                controller: _password,
                label: 'Master password',
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              PassphraseStrengthBar(passphrase: _password.text),
              const SizedBox(height: Space.md),
              PassphraseField(
                controller: _confirm,
                label: 'Master password again',
                onSubmitted: _submit,
              ),
              if (canRemember) ...[
                const SizedBox(height: Space.sm),
                CheckboxListTile(
                  value: _remember,
                  onChanged: (value) =>
                      setState(() => _remember = value ?? false),
                  title: const Text('Remember it in the system keyring'),
                  subtitle: const Text(
                    'Anyone with your unlocked account can '
                    'then open your keys.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ],
              const SizedBox(height: Space.sm),
              const InlineMessage(
                title: 'There is no way to recover this password.',
                hint:
                    'Forget it and the private keys in this keyring are gone.',
                tone: MessageTone.warning,
              ),
            ],
            if (_fieldError != null) ...[
              const SizedBox(height: Space.md),
              InlineMessage(title: _fieldError!),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              InlineMessage.forError(_error!),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg,
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Continue',
          kind: AppButtonKind.primary,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      onTap: onTap,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.small),
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelMedium),
                      const SizedBox(height: Space.xs),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> unlockKeyring(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const _UnlockDialog(),
  );
  return result ?? false;
}

class _UnlockDialog extends ConsumerStatefulWidget {
  const _UnlockDialog();

  @override
  ConsumerState<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends ConsumerState<_UnlockDialog> {
  final _password = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(keyringProvider.notifier)
          .unlock(_password.text, remember: _remember);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is WrongPassphrase
              ? const WrongMasterPassword()
              : error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRemember = ref
        .read(storageServiceProvider)
        .canRememberMasterPassword;
    return AlertDialog(
      title: const Text('Unlock your keyring'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PassphraseField(
            controller: _password,
            label: 'Master password',
            autofocus: true,
            onSubmitted: _submit,
          ),
          if (canRemember)
            CheckboxListTile(
              value: _remember,
              onChanged: (value) => setState(() => _remember = value ?? false),
              title: const Text('Remember it in the system keyring'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            InlineMessage.forError(_error!),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.lg,
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.quiet,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Unlock',
          kind: AppButtonKind.primary,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// makes sure the vault is ready to take a private key, asking only if it
/// has to. false when the dialog was backed out of
Future<bool> ensureVaultReady(BuildContext context, WidgetRef ref) async {
  final state = ref.read(keyringProvider);
  return switch (state.status) {
    VaultStatus.unlocked || VaultStatus.sessionOnly => true,
    VaultStatus.locked => unlockKeyring(context),
    VaultStatus.empty => chooseKeyringMode(context),
  };
}

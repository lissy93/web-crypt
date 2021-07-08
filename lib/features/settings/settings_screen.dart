import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/app_card.dart';
import 'package:web_crypt/core/widgets/confirm_dialog.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/core/widgets/passphrase_field.dart';
import 'package:web_crypt/core/widgets/segmented.dart';
import 'package:web_crypt/features/decrypt/decrypt_controller.dart';
import 'package:web_crypt/features/encrypt/encrypt_controller.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/settings/about_panel.dart';
import 'package:web_crypt/features/shared/screen_scaffold.dart';
import 'package:web_crypt/services/storage_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final choice = ref.watch(themeChoiceProvider);
    final keyring = ref.watch(keyringProvider);

    return ScreenScaffold(
      title: 'Settings',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Appearance'),
              AppSegmented<ThemeChoice>(
                label: 'Theme',
                value: choice,
                onChanged: ref.read(themeChoiceProvider.notifier).set,
                options: const [
                  SegmentedOption(value: ThemeChoice.system, label: 'System'),
                  SegmentedOption(value: ThemeChoice.light, label: 'Light'),
                  SegmentedOption(value: ThemeChoice.dark, label: 'Dark'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        const _KeyringSection(),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel(
                'Local data',
                hint: 'Everything web-crypt stores lives on this device only.',
              ),
              Text(
                'Theme, your last format and mode, your public keys, and your '
                'encrypted private keyring.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.lg),
              AppButton(
                label: 'Clear all local data',
                icon: Icons.delete_outline,
                kind: AppButtonKind.danger,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Clear all local data?',
                    message: keyring.hasPrivateKeys
                        ? 'This removes every key, including '
                              '${keyring.keys.where((k) => k.hasPrivate).length} '
                              'private one(s). Anything encrypted to them becomes '
                              'unreadable. There is no undo.'
                        : 'This removes your keys and preferences. There is no '
                              'undo.',
                    confirmLabel: 'Clear everything',
                  );
                  if (!ok || !context.mounted) return;
                  await ref.read(keyringProvider.notifier).clearAll();
                  // these read their preference once, so it is now stale
                  ref
                    ..invalidate(decryptProvider)
                    ..invalidate(encryptProvider)
                    ..invalidate(themeChoiceProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Local data cleared')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        const AboutPanel(),
      ],
    );
  }
}

class _KeyringSection extends ConsumerStatefulWidget {
  const _KeyringSection();

  @override
  ConsumerState<_KeyringSection> createState() => _KeyringSectionState();
}

class _KeyringSectionState extends ConsumerState<_KeyringSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmNext = TextEditingController();
  bool _changing = false;
  bool _busy = false;
  Object? _error;
  String? _fieldError;

  @override
  void dispose() {
    _current.clear();
    _next.clear();
    _confirmNext.clear();
    _current.dispose();
    _next.dispose();
    _confirmNext.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_next.text.isEmpty) {
      setState(() => _fieldError = 'Choose a new master password.');
      return;
    }
    if (_next.text != _confirmNext.text) {
      setState(() => _fieldError = 'The two do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      await ref
          .read(keyringProvider.notifier)
          .changeMasterPassword(_current.text, _next.text);
      _current.clear();
      _next.clear();
      _confirmNext.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _changing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master password changed')),
        );
      }
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
    final theme = Theme.of(context);
    final state = ref.watch(keyringProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Keyring'),
          Text(switch (state.status) {
            VaultStatus.empty =>
              'No private keys are stored. You will be asked how to keep '
                  'them the first time you save one.',
            VaultStatus.sessionOnly =>
              'Private keys are held in memory for this session only.',
            VaultStatus.unlocked =>
              'Unlocked. Your private keys are a standard age file, '
                  'encrypted under your master password.',
            VaultStatus.locked => 'Locked. Unlock to use your private keys.',
          }, style: theme.textTheme.bodySmall),
          if (_changing) ...[
            const SizedBox(height: Space.lg),
            PassphraseField(
              controller: _current,
              label: 'Current master password',
              autofocus: true,
            ),
            const SizedBox(height: Space.md),
            PassphraseField(controller: _next, label: 'New master password'),
            const SizedBox(height: Space.md),
            PassphraseField(
              controller: _confirmNext,
              label: 'New master password again',
              errorText: _fieldError,
              onSubmitted: _change,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            InlineMessage.forError(_error!),
          ],
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              if (state.status == VaultStatus.unlocked) ...[
                AppButton(
                  label: _changing
                      ? 'Save new password'
                      : 'Change master password',
                  icon: Icons.password_outlined,
                  kind: _changing
                      ? AppButtonKind.primary
                      : AppButtonKind.secondary,
                  busy: _busy,
                  onPressed: _changing
                      ? _change
                      : () => setState(() => _changing = true),
                ),
                if (_changing)
                  AppButton(
                    label: 'Cancel',
                    kind: AppButtonKind.quiet,
                    onPressed: () => setState(() {
                      _changing = false;
                      _fieldError = null;
                      _error = null;
                    }),
                  ),
                AppButton(
                  label: 'Lock now',
                  icon: Icons.lock_outline,
                  onPressed: () async {
                    await ref.read(keyringProvider.notifier).lock();
                    // any plaintext still on the Decrypt screen goes too
                    ref.invalidate(decryptProvider);
                  },
                ),
              ],
              if (state.status == VaultStatus.sessionOnly)
                Text(
                  'Session keys cannot be locked, only forgotten.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.textFaint,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

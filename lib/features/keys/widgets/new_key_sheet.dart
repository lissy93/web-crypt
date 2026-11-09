import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/core/widgets/passphrase_field.dart';
import 'package:web_crypt/core/widgets/segmented.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/keys/widgets/keyring_dialogs.dart';

Future<String?> showNewKeySheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _NewKeySheet(),
  );
}

class _NewKeySheet extends ConsumerStatefulWidget {
  const _NewKeySheet();

  @override
  ConsumerState<_NewKeySheet> createState() => _NewKeySheetState();
}

class _NewKeySheetState extends ConsumerState<_NewKeySheet> {
  CryptoFormatKind _format = CryptoFormatKind.age;
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _passphrase = TextEditingController();
  final _expiryDays = TextEditingController();
  bool _busy = false;
  Object? _error;
  String? _fieldError;

  @override
  void dispose() {
    _passphrase.clear();
    _label.dispose();
    _name.dispose();
    _email.dispose();
    _passphrase.dispose();
    _expiryDays.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_format == CryptoFormatKind.pgp &&
        _name.text.trim().isEmpty &&
        _email.text.trim().isEmpty) {
      setState(() => _fieldError = 'PGP keys need a name or an email.');
      return;
    }
    final days = int.tryParse(_expiryDays.text.trim());
    if (_expiryDays.text.trim().isNotEmpty && (days == null || days <= 0)) {
      setState(() => _fieldError = 'Expiry must be a number of days.');
      return;
    }

    if (!await ensureVaultReady(context, ref)) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      final controller = ref.read(keyringProvider.notifier);
      final entry = _format == CryptoFormatKind.age
          ? await controller.generateAgeKey(label: _label.text.trim())
          : await controller.generatePgpKey(
              name: _name.text.trim(),
              email: _email.text.trim(),
              passphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
              expiry: days == null ? null : Duration(days: days),
              label: _label.text.trim(),
            );
      if (mounted) Navigator.of(context).pop(entry.id);
    } on AppException catch (error) {
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
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        top: Space.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('New key', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.lg),
            AppSegmented<CryptoFormatKind>(
              label: 'Key type',
              value: _format,
              onChanged: (value) => setState(() => _format = value),
              options: const [
                SegmentedOption(value: CryptoFormatKind.age, label: 'age'),
                SegmentedOption(value: CryptoFormatKind.pgp, label: 'PGP'),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(
              _format == CryptoFormatKind.age
                  ? 'A short X25519 keypair. Give people the age1… line and '
                        'they can encrypt to you.'
                  : 'An Ed25519 key with a Curve25519 encryption subkey. '
                        'Works with GnuPG and anything that speaks OpenPGP.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.xl),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'What you will call it here (optional)',
              ),
            ),
            if (_format == CryptoFormatKind.pgp) ...[
              const SizedBox(height: Space.md),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: Space.md),
              PassphraseField(
                controller: _passphrase,
                label: 'Key passphrase (optional)',
                hint: 'Protects the key itself, on top of your keyring',
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: _expiryDays,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Expires after (days, optional)',
                  hintText: 'Leave empty for no expiry',
                ),
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
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Create key',
                    kind: AppButtonKind.primary,
                    icon: Icons.add,
                    busy: _busy,
                    expand: true,
                    onPressed: _create,
                  ),
                ),
                const SizedBox(width: Space.sm),
                AppButton(
                  label: 'Cancel',
                  kind: AppButtonKind.quiet,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

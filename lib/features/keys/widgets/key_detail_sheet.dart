import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/confirm_dialog.dart';
import 'package:web_crypt/core/widgets/copy_field.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/crypto/age/age_keys.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/keys/widgets/keyring_dialogs.dart';

Future<void> showKeyDetail(BuildContext context, String keyId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _KeyDetailSheet(keyId: keyId),
  );
}

class _KeyDetailSheet extends ConsumerStatefulWidget {
  const _KeyDetailSheet({required this.keyId});

  final String keyId;

  @override
  ConsumerState<_KeyDetailSheet> createState() => _KeyDetailSheetState();
}

class _KeyDetailSheetState extends ConsumerState<_KeyDetailSheet> {
  late final TextEditingController _label;
  String? _revealed;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final entry = ref.read(keyringProvider.notifier).byId(widget.keyId);
    _label = TextEditingController(text: entry?.label ?? '');
  }

  @override
  void dispose() {
    _revealed = null;
    _label.dispose();
    super.dispose();
  }

  Future<void> _revealPrivate(KeyEntry entry) async {
    if (!await confirmPrivateKeyExport(context, keyName: entry.displayName)) {
      return;
    }
    if (!mounted) return;
    if (!await ensureVaultReady(context, ref)) return;
    if (!mounted) return;

    final material = ref
        .read(keyringProvider.notifier)
        .privateMaterialFor(entry.id);
    if (material == null) {
      setState(() => _error = const KeyringLocked());
      return;
    }
    setState(() {
      _error = null;
      _revealed = entry.format == CryptoFormatKind.age
          ? ageIdentityFile(material, entry.publicMaterial, entry.createdAt)
          : material;
    });
  }

  Future<void> _exportPublic(KeyEntry entry) async {
    final name = entry.format == CryptoFormatKind.age
        ? '${_fileStem(entry)}-recipient.txt'
        : '${_fileStem(entry)}-public.asc';
    await _save(name, entry.publicMaterial);
  }

  Future<void> _exportPrivate(KeyEntry entry) async {
    if (!await confirmPrivateKeyExport(context, keyName: entry.displayName)) {
      return;
    }
    if (!mounted) return;
    if (!await ensureVaultReady(context, ref)) return;
    if (!mounted) return;

    final material = ref
        .read(keyringProvider.notifier)
        .privateMaterialFor(entry.id);
    if (material == null) {
      setState(() => _error = const KeyringLocked());
      return;
    }
    final contents = entry.format == CryptoFormatKind.age
        ? ageIdentityFile(material, entry.publicMaterial, entry.createdAt)
        : material;
    final name = entry.format == CryptoFormatKind.age
        ? '${_fileStem(entry)}-identity.txt'
        : '${_fileStem(entry)}-private.asc';
    await _save(name, contents);
  }

  Future<void> _save(String name, String contents) async {
    try {
      await ref
          .read(fileServiceProvider)
          .saveBytes(suggestedName: name, bytes: utf8.encode(contents));
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _delete(KeyEntry entry) async {
    final ok = await confirm(
      context,
      title: 'Delete "${entry.displayName}"?',
      message: entry.hasPrivate
          ? 'The private key goes with it. Anything encrypted to this key '
                'becomes unreadable unless you have a copy elsewhere.'
          : 'You can import it again later if you keep a copy.',
    );
    if (!ok || !mounted) return;
    // the vault holds the private half, and has to be open to delete from it
    if (entry.hasPrivate) {
      if (!await ensureVaultReady(context, ref)) return;
      if (!mounted) return;
    }
    try {
      await ref.read(keyringProvider.notifier).delete(entry.id);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  static String _fileStem(KeyEntry entry) {
    final base = entry.displayName
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    return base.isEmpty ? 'key' : base;
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref
        .watch(keyringProvider)
        .keys
        .where((key) => key.id == widget.keyId);
    if (entry.isEmpty) return const SizedBox.shrink();
    final key = entry.first;
    final theme = Theme.of(context);
    final colors = context.colors;

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
              child: Text(key.displayName, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${key.format.label} '
              '${key.hasPrivate ? 'keypair' : 'public key'} '
              '· added ${formatDate(key.createdAt)}'
              '${key.expiresAt == null ? '' : ' · expires ${formatDate(key.expiresAt!)}'}',
              style: theme.textTheme.bodySmall,
            ),
            if (key.isExpired) ...[
              const SizedBox(height: Space.md),
              const InlineMessage(
                title: 'This key has expired.',
                hint: 'Other tools will refuse to encrypt to it.',
                tone: MessageTone.warning,
              ),
            ],
            const SizedBox(height: Space.xl),
            Text(
              key.format == CryptoFormatKind.age ? 'Recipient' : 'Fingerprint',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: Space.sm),
            CopyField(
              value: key.format == CryptoFormatKind.age
                  ? key.publicMaterial
                  : groupFingerprint(key.fingerprint),
              label: key.format == CryptoFormatKind.age
                  ? 'Recipient'
                  : 'Fingerprint',
              maxLines: 3,
            ),
            const SizedBox(height: Space.xl),
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
              onSubmitted: (value) => ref
                  .read(keyringProvider.notifier)
                  .rename(key.id, value.trim()),
            ),
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Save label',
                onPressed: () => ref
                    .read(keyringProvider.notifier)
                    .rename(key.id, _label.text.trim()),
              ),
            ),
            if (_revealed != null) ...[
              const SizedBox(height: Space.xl),
              Text('Private key', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.sm),
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.dangerMuted,
                  border: Border.all(
                    color: colors.danger.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(Radii.small),
                ),
                child: CopyField(
                  value: _revealed!,
                  label: 'Private key',
                  sensitive: true,
                  maxLines: 8,
                ),
              ),
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'Hide',
                kind: AppButtonKind.quiet,
                onPressed: () => setState(() => _revealed = null),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              InlineMessage.forError(_error!),
            ],
            const SizedBox(height: Space.xl),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                AppButton(
                  label: 'Export public',
                  icon: Icons.download_outlined,
                  onPressed: () => _exportPublic(key),
                ),
                if (key.hasPrivate) ...[
                  AppButton(
                    label: _revealed == null ? 'Reveal private' : 'Revealed',
                    icon: Icons.visibility_outlined,
                    kind: AppButtonKind.danger,
                    onPressed: _revealed == null
                        ? () => _revealPrivate(key)
                        : null,
                  ),
                  AppButton(
                    label: 'Export private',
                    icon: Icons.download_outlined,
                    kind: AppButtonKind.danger,
                    onPressed: () => _exportPrivate(key),
                  ),
                ],
                AppButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  kind: AppButtonKind.danger,
                  onPressed: () => _delete(key),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

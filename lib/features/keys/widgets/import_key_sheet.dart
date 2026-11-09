import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/drop_zone.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/keys/widgets/keyring_dialogs.dart';
import 'package:web_crypt/services/file_service.dart';

Future<String?> showImportKeySheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ImportKeySheet(),
  );
}

class _ImportKeySheet extends ConsumerStatefulWidget {
  const _ImportKeySheet();

  @override
  ConsumerState<_ImportKeySheet> createState() => _ImportKeySheetState();
}

class _ImportKeySheetState extends ConsumerState<_ImportKeySheet> {
  final _text = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _text.clear();
    _text.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _importText() => _import(_text.text);

  Future<void> _importFiles(List<PickedFile> files) async {
    try {
      await _import(
        utf8.decode(await files.first.read(), allowMalformed: true),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _import(String material) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // read first, so the keyring question only comes up for a private key
      final preview = await parseKeyMaterial(
        material,
        id: 'preview',
        now: DateTime.now(),
      );
      if (preview.isPrivate) {
        if (!mounted) return;
        if (!await ensureVaultReady(context, ref)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
      final parsed = await ref
          .read(keyringProvider.notifier)
          .importText(material, label: _label.text.trim());
      if (mounted) Navigator.of(context).pop(parsed.entry.id);
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
              child: Text('Import a key', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.xs),
            Text(
              'age recipients and identities, or armored PGP keys. '
              'We work out which it is.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.lg),
            DropZone(
              title: 'Drop a key file, or browse',
              icon: Icons.key_outlined,
              compact: true,
              onFiles: _importFiles,
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              style: monoStyle(context),
              decoration: const InputDecoration(
                labelText: 'Or paste it here',
                hintText: 'age1… or -----BEGIN PGP PUBLIC KEY BLOCK-----',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'What you will call it here (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              InlineMessage.forError(_error!),
            ],
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Import',
                    kind: AppButtonKind.primary,
                    busy: _busy,
                    expand: true,
                    onPressed: _text.text.trim().isEmpty ? null : _importText,
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

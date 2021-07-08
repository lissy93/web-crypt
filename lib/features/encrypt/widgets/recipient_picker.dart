import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/crypto/keyring/key_import.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';

/// chips for chosen recipients, plus three ways to add one: the keyring, a
/// pasted key, or a key file
class RecipientPicker extends ConsumerStatefulWidget {
  const RecipientPicker({
    required this.format,
    required this.selected,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final CryptoFormatKind format;
  final List<Recipient> selected;
  final ValueChanged<Recipient> onAdd;
  final ValueChanged<Recipient> onRemove;

  @override
  ConsumerState<RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends ConsumerState<RecipientPicker> {
  final _pasteController = TextEditingController();
  bool _pasting = false;
  Object? _error;

  @override
  void dispose() {
    _pasteController.clear();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _addPasted() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;
    await _addFromText(text);
  }

  Future<void> _addFromText(String text) async {
    setState(() => _error = null);
    try {
      final parsed = await parseKeyMaterial(
        text,
        id: 'pasted',
        now: DateTime.now(),
      );
      if (parsed.entry.format != widget.format) {
        setState(() => _error = const RecipientFormatMismatch());
        return;
      }
      widget.onAdd(parsed.entry.asRecipient);
      _pasteController.clear();
      setState(() => _pasting = false);
    } on AppException catch (error) {
      setState(() => _error = error);
    }
  }

  Future<void> _addFromFile() async {
    setState(() => _error = null);
    try {
      final files = await ref
          .read(fileServiceProvider)
          .pickFiles(allowMultiple: false);
      if (files.isEmpty) return;
      final bytes = await files.first.read();
      await _addFromText(utf8.decode(bytes, allowMalformed: true));
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final keyring = ref.watch(keyringProvider);
    final available = keyring
        .recipientsFor(widget.format)
        .where(
          (key) =>
              !widget.selected.any((r) => r.material == key.publicMaterial),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isEmpty)
          Text(
            'Nobody can open this yet. Add at least one recipient.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final recipient in widget.selected)
                _RecipientChip(
                  recipient: recipient,
                  onRemove: () => widget.onRemove(recipient),
                ),
            ],
          ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            if (available.isNotEmpty)
              _KeyringMenu(
                keys: available,
                onSelected: (key) => widget.onAdd(key.asRecipient),
              ),
            AppButton(
              label: _pasting ? 'Cancel paste' : 'Paste a key',
              icon: _pasting ? Icons.close : Icons.content_paste_outlined,
              onPressed: () => setState(() {
                _pasting = !_pasting;
                _error = null;
              }),
            ),
            AppButton(
              label: 'From file',
              icon: Icons.folder_open_outlined,
              onPressed: _addFromFile,
            ),
          ],
        ),
        if (_pasting) ...[
          const SizedBox(height: Space.md),
          TextField(
            controller: _pasteController,
            maxLines: 4,
            minLines: 2,
            autofocus: true,
            style: monoStyle(context),
            decoration: InputDecoration(
              hintText: widget.format == CryptoFormatKind.age
                  ? 'age1...'
                  : '-----BEGIN PGP PUBLIC KEY BLOCK-----',
            ),
          ),
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Add recipient',
            kind: AppButtonKind.secondary,
            onPressed: _addPasted,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.md),
          InlineMessage.forError(_error!),
        ],
        if (available.isEmpty && widget.selected.isEmpty && !_pasting) ...[
          const SizedBox(height: Space.sm),
          Text(
            'You have no ${widget.format.label} public keys saved. '
            'Paste one, or add one on the Keys screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textFaint),
          ),
        ],
      ],
    );
  }
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({required this.recipient, required this.onRemove});

  final Recipient recipient;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: Space.md, right: Space.xs),
      decoration: BoxDecoration(
        color: colors.accentMuted,
        border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ellipsise(recipient.label, 32),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(width: Space.xs),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Remove ${recipient.label}',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _KeyringMenu extends StatelessWidget {
  const _KeyringMenu({required this.keys, required this.onSelected});

  final List<KeyEntry> keys;
  final ValueChanged<KeyEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => AppButton(
        label: 'From keyring',
        icon: Icons.key_outlined,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final key in keys)
          MenuItemButton(
            onPressed: () => onSelected(key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(key.displayName),
                  Text(
                    ellipsise(key.fingerprint, 40),
                    style: monoStyle(context, size: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

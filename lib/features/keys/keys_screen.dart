import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/utils/formatters.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/app_card.dart';
import 'package:web_crypt/core/widgets/inline_message.dart';
import 'package:web_crypt/crypto/format.dart';
import 'package:web_crypt/crypto/keyring/key_entry.dart';
import 'package:web_crypt/features/keys/keyring_controller.dart';
import 'package:web_crypt/features/keys/widgets/import_key_sheet.dart';
import 'package:web_crypt/features/keys/widgets/key_detail_sheet.dart';
import 'package:web_crypt/features/keys/widgets/keyring_dialogs.dart';
import 'package:web_crypt/features/keys/widgets/new_key_sheet.dart';
import 'package:web_crypt/features/shared/screen_scaffold.dart';

class KeysScreen extends ConsumerWidget {
  const KeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(keyringProvider);

    return ScreenScaffold(
      title: 'Keys',
      subtitle:
          'Public keys let people encrypt to you. Private keys let you read what they send.',
      children: [
        if (state.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(Space.xxl),
              child: CircularProgressIndicator(),
            ),
          )
        else ...[
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              AppButton(
                label: 'New key',
                icon: Icons.add,
                kind: AppButtonKind.primary,
                onPressed: () async {
                  final id = await showNewKeySheet(context);
                  if (id != null && context.mounted) {
                    await showKeyDetail(context, id);
                  }
                },
              ),
              AppButton(
                label: 'Import',
                icon: Icons.download_outlined,
                onPressed: () async {
                  final id = await showImportKeySheet(context);
                  if (id != null && context.mounted) {
                    await showKeyDetail(context, id);
                  }
                },
              ),
            ],
          ),
          if (state.isLocked) ...[
            const SizedBox(height: Space.lg),
            const _LockedBanner(),
          ],
          if (state.status == VaultStatus.sessionOnly &&
              state.hasPrivateKeys) ...[
            const SizedBox(height: Space.lg),
            const InlineMessage(
              title: 'Private keys are session only.',
              hint:
                  'They disappear when you close web-crypt. Export any you '
                  'want to keep.',
              tone: MessageTone.info,
            ),
          ],
          const SizedBox(height: Space.xl),
          if (state.keys.isEmpty)
            const _EmptyState()
          else ...[
            for (final format in CryptoFormatKind.values)
              if (state.byFormat(format).isNotEmpty) ...[
                _KeyGroup(format: format, keys: state.byFormat(format)),
                const SizedBox(height: Space.xl),
              ],
          ],
        ],
      ],
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return InlineMessage(
      title: 'Your keyring is locked.',
      hint:
          'Your private keys are here, but nothing can use them until you '
          'unlock.',
      tone: MessageTone.warning,
      action: AppButton(
        label: 'Unlock',
        icon: Icons.lock_open_outlined,
        onPressed: () => unlockKeyring(context),
      ),
    );
  }
}

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({required this.format, required this.keys});

  final CryptoFormatKind format;
  final List<KeyEntry> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(format.label, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: Space.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < keys.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _KeyRow(entry: keys[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.entry});

  final KeyEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showKeyDetail(context, entry.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(
              entry.hasPrivate ? Icons.key : Icons.vpn_key_outlined,
              size: 20,
              color: entry.hasPrivate ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        entry.displayName,
                        style: theme.textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.hasPrivate)
                        _Tag(label: 'private', colour: colors.accent),
                      if (entry.isExpired)
                        _Tag(label: 'expired', colour: colors.warning),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    entry.format == CryptoFormatKind.age
                        ? ellipsise(entry.publicMaterial, 44)
                        : groupFingerprint(shortFingerprint(entry.fingerprint)),
                    style: monoStyle(
                      context,
                      size: 12,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(
              formatDate(entry.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textFaint,
              ),
            ),
            const SizedBox(width: Space.sm),
            Icon(Icons.chevron_right, size: 18, color: colors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 1),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.small / 2),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colour, fontSize: 11),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      muted: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No keys yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.md),
          Text(
            'age keys are short and simple: hand out one line and people can '
            'encrypt files to you.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.sm),
          Text(
            'PGP keys are the older standard, and work with GnuPG, Thunderbird '
            'and most mail tools.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          Text(
            'You only need keys for recipient mode. Passphrase encryption '
            'works without any.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_button.dart';
import 'package:web_crypt/core/widgets/app_card.dart';

/// kept in step with pubspec.yaml
const appVersion = '1.0.0';

const _links = [
  ('Source', 'https://github.com/lissy93/web-crypt'),
  ('age spec', 'https://age-encryption.org/v1'),
  ('OpenPGP', 'https://www.rfc-editor.org/rfc/rfc9580.html'),
];

class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('About'),
          Text('web-crypt $appVersion', style: theme.textTheme.labelMedium),
          const SizedBox(height: Space.sm),
          Text(
            'Encrypts with age and OpenPGP, and nothing else. Everything '
            'happens in this app: no accounts, no servers, no network '
            'requests, no telemetry.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          Text('What it protects', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Your data at rest, and in transit between you and whoever you '
            'send it to. It cannot protect you from a device or browser that '
            'is already compromised.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          Text('Links', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          // plain text on purpose, nothing here opens a connection
          for (final (label, url) in _links)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Layout.minTapTarget),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(label, style: theme.textTheme.bodySmall),
                  ),
                  Expanded(
                    child: SelectableText(
                      url,
                      style: monoStyle(
                        context,
                        size: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.lg),
          AppButton(
            label: 'Licences',
            icon: Icons.article_outlined,
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'web-crypt',
              applicationVersion: appVersion,
              applicationLegalese:
                  'MIT licensed. Fonts under the SIL Open '
                  'Font License.',
            ),
          ),
        ],
      ),
    );
  }
}

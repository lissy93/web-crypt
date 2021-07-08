import 'package:flutter/material.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_button.dart';

/// destructive actions always name the thing they will destroy
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
          label: confirmLabel,
          kind: destructive ? AppButtonKind.danger : AppButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// shown before a private key is written or copied anywhere
Future<bool> confirmPrivateKeyExport(
  BuildContext context, {
  required String keyName,
}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_outlined, color: colors.warning),
      title: const Text('This is a private key'),
      content: Text(
        'You are about to reveal the private half of "$keyName". Anyone who '
        'gets it can decrypt everything sent to that key. Only put it '
        'somewhere you trust.',
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
          label: 'I understand',
          kind: AppButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

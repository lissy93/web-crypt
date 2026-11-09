import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:web_crypt/app/theme/app_colors.dart';
import 'package:web_crypt/app/theme/app_theme.dart';
import 'package:web_crypt/app/theme/spacing.dart';
import 'package:web_crypt/core/widgets/app_button.dart';

/// says what the clipboard means for anything sensitive
Future<void> copyToClipboard(
  BuildContext context,
  String value, {
  required String what,
  bool sensitive = false,
}) async {
  var copied = true;
  try {
    await Clipboard.setData(ClipboardData(text: value));
  } on Object {
    copied = false;
  }
  if (!context.mounted) return;

  final String message;
  if (!copied) {
    message =
        'The clipboard could not be reached. Select the text and copy '
        'it yourself.';
  } else if (sensitive) {
    message =
        '$what copied. Other apps can read your clipboard, so paste it '
        'soon and clear it.';
  } else {
    message = '$what copied';
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: Duration(seconds: copied && !sensitive ? 2 : 6),
    ),
  );
  if (!copied) return;
  await SemanticsService.sendAnnouncement(
    View.of(context),
    '$what copied',
    Directionality.of(context),
  );
}

class CopyField extends StatelessWidget {
  const CopyField({
    required this.value,
    required this.label,
    this.sensitive = false,
    this.maxLines = 2,
    super.key,
  });

  final String value;
  final String label;
  final bool sensitive;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: SelectableText(
                value,
                maxLines: maxLines,
                style: monoStyle(context),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.copy_outlined,
            tooltip: 'Copy $label',
            onPressed: () => copyToClipboard(
              context,
              value,
              what: label,
              sensitive: sensitive,
            ),
          ),
        ],
      ),
    );
  }
}

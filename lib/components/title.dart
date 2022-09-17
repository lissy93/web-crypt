import 'package:flutter/material.dart';
import '../utils/color-palette.dart' as colors;

Widget title(BuildContext context, String titleText) {
  return Center(
    child: Text(
      titleText,
      style: const TextStyle(
        color: colors.primary,
        fontSize: 120,
        fontWeight: FontWeight.bold,
        fontFamily: 'Lobster',
      ),
    ),
  );
}

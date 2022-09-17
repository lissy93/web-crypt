import 'package:flutter/material.dart';
import '../utils/app-text.dart';
import '../utils/color-palette.dart' as colors;

Widget outputSection(output) {
  return Column(
    children: [
      const SizedBox(height: 50),
      const Text(
        outputText,
        textScaleFactor: 1.2,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colors.text,
        ),
      ),
      Text(
        '$output',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: colors.text,
        ),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import '../utils/color-palette.dart' as colors;

Widget mainContainer(BuildContext context, List<Widget> children) {
  return Center(
    child: Container(
      margin: const EdgeInsets.all(10.0),
      padding: const EdgeInsets.all(10.0),
      color: colors.backgroundLighter,
      constraints: const BoxConstraints(
        minHeight: 500, //minimum height
        minWidth: 300, // minimum width
        // maxHeight: MediaQuery.of(context).size.height * 0.8,
        maxWidth: 800,
      ),
      child: Column(
        children: children,
      ),
    ),
  );
}

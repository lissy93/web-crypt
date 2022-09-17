import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert' show utf8;

import 'package:convert/convert.dart' show hex;
import 'package:webcrypto/webcrypto.dart';

import 'utils/color-palette.dart' as colors;
import 'utils/app-text.dart';

import 'components/title.dart';
import 'components/main_container.dart';
import 'components/input_section.dart';
import 'components/output_section.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

ThemeData buildDarkTheme() {
  final ThemeData base = ThemeData();
  return base.copyWith(
    primaryColor: colors.primary,
    scaffoldBackgroundColor: colors.background,
    primaryIconTheme: base.iconTheme.copyWith(color: colors.primary),
    hintColor: colors.primary,
    inputDecorationTheme: InputDecorationTheme(
      // border: OutlineInputBorder(),
      labelStyle: TextStyle(color: colors.primary, fontSize: 24.0),
    ),
  );
}

class _MyAppState extends State<MyApp> {
  String _output = '-';
  final _input = TextEditingController();

  final materialAppTheme = ThemeData(
    scaffoldBackgroundColor: colors.background,
    fontFamily: 'RobotoMono',
    primaryColor: colors.primary,
    // primarySwatch: Colors.red,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: mainContainer(
          context,
          [
            title(context, titleText),
            inputSection(_input, _refreshHash),
            outputSection(_output)
          ],
        ),
      ),
    );
  }

  Future<void> _refreshHash() async {
    final result = await Hash.sha1.digestBytes(utf8.encode(_input.text));
    setState(() {
      _output = hex.encode(result);
    });
  }
}

import 'package:flutter/material.dart';
import '../utils/app-text.dart';
import '../utils/color-palette.dart' as colors;

OutlineInputBorder inputBorderDefault(bool _isSelected) {
  // const borderWidth = _isSelected ? 4 : 2;
  return OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(
        color: colors.primary,
        width: _isSelected ? 3 : 2,
      ));
}

ButtonStyle buttonStyle() {
  // const borderWidth = _isSelected ? 4 : 2;
  return ElevatedButton.styleFrom(
    primary: colors.primary,
    elevation: 2,
  );
}

Widget inputSection(controller, action) {
  return Column(children: [
    const Text(
      inputText,
      textScaleFactor: 1.2,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: colors.text,
      ),
    ),
    Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            keyboardType: TextInputType.multiline,
            maxLines: null,
            minLines: 5,
            style: const TextStyle(
              color: colors.text,
              fontFamily: 'RobotoMono',
            ),
            decoration: InputDecoration(
              border: inputBorderDefault(false),
              focusedBorder: inputBorderDefault(true),
              enabledBorder: inputBorderDefault(false),
              hintText: 'Enter text to encrypt',
              // labelText: "Input",
              contentPadding: const EdgeInsets.all(12.0),
              focusColor: colors.primary,
            ),
            controller: controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        // IconButton(
        //   icon: const Icon(Icons.autorenew),
        //   tooltip: 'compute hash',
        //   onPressed: action,
        // ),
      ],
    ),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          child: Text(
            "Encrypt",
            style: new TextStyle(
              fontSize: 20.0,
              fontFamily: 'RobotoMono',
              color: colors.text,
            ),
          ),
          style: buttonStyle(),
          onPressed: action,
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: ElevatedButton(
          child: Text(
            "Decrypt",
            style: const TextStyle(
              fontSize: 20.0,
              fontFamily: 'RobotoMono',
              color: colors.text,
            ),
          ),
          style: buttonStyle(),
          onPressed: () {},
        ),
      ),
    ]),
  ]);
}

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/core/utils/streams.dart';
import 'package:web_crypt/services/file_service.dart';

const canStreamToDisk = true;

Future<List<PickedFile>> pickFiles({bool allowMultiple = true}) async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      withData: false,
    );
  } on Object {
    throw const FileAccessFailed();
  }
  if (result == null) return const [];
  return [
    for (final file in result.files)
      if (file.path != null)
        PickedFile(name: file.name, size: file.size, path: file.path),
  ];
}

Future<String?> saveBytes({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  final path = await chooseSavePath(suggestedName: suggestedName);
  if (path == null) return null;
  try {
    await File(path).writeAsBytes(bytes, flush: true);
  } on FileSystemException {
    throw const FileAccessFailed();
  }
  return path;
}

Future<String?> chooseSavePath({required String suggestedName}) async {
  try {
    return await FilePicker.saveFile(
      fileName: suggestedName,
      lockParentWindow: true,
    );
  } on Object {
    throw const FileAccessFailed();
  }
}

Future<Uint8List> readFileBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } on FileSystemException {
    throw const FileAccessFailed();
  }
}

Future<Uint8List> readFileHead(String path, int count) async {
  try {
    return await collectBytes(File(path).openRead(0, count));
  } on FileSystemException {
    throw const FileAccessFailed();
  }
}

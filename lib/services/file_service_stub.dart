import 'dart:typed_data';

import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/services/file_service.dart';

const canStreamToDisk = false;

Future<List<PickedFile>> pickFiles({bool allowMultiple = true}) async =>
    const [];

Future<String?> saveBytes({
  required String suggestedName,
  required Uint8List bytes,
}) async => throw const FileAccessFailed();

Future<String?> chooseSavePath({required String suggestedName}) async => null;

Future<Uint8List> readFileBytes(String path) async =>
    throw const FileAccessFailed();

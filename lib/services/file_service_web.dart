import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/services/file_service.dart';

const canStreamToDisk = false;

Future<List<PickedFile>> pickFiles({bool allowMultiple = true}) async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      withData: true,
    );
  } on Object {
    throw const FileAccessFailed();
  }
  if (result == null) return const [];
  // the picker keeps a second copy behind a blob url, which is never used
  for (final file in result.files) {
    if (file.path case final url?) web.URL.revokeObjectURL(url);
  }
  return [
    for (final file in result.files)
      if (file.bytes != null)
        PickedFile(name: file.name, size: file.size, bytes: file.bytes),
  ];
}

/// hands the bytes to the browser as a download. nothing leaves the tab, the
/// blob url is local and revoked straight after
Future<String?> saveBytes({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = suggestedName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return null;
}

Future<String?> chooseSavePath({required String suggestedName}) async => null;

Future<Uint8List> readFileBytes(String path) async {
  throw const FileAccessFailed();
}

Future<Uint8List> readFileHead(String path, int count) async {
  throw const FileAccessFailed();
}

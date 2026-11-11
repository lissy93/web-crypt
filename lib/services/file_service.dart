import 'dart:math';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:web_crypt/core/errors/app_exception.dart';
import 'package:web_crypt/services/file_service_stub.dart'
    if (dart.library.io) 'package:web_crypt/services/file_service_io.dart'
    if (dart.library.js_interop) 'package:web_crypt/services/file_service_web.dart'
    as platform;

/// native gets a [path] and streams from disk, web only ever has [bytes]
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;

  Future<Uint8List> read() async {
    final loaded = bytes;
    if (loaded != null) return loaded;
    final source = path;
    if (source == null) throw const FileAccessFailed();
    return platform.readFileBytes(source);
  }

  /// the first [count] bytes, leaving the rest on disk
  Future<Uint8List> readHead(int count) async {
    final loaded = bytes;
    if (loaded != null) {
      return Uint8List.sublistView(loaded, 0, min(count, loaded.length));
    }
    final source = path;
    if (source == null) throw const FileAccessFailed();
    return platform.readFileHead(source, count);
  }

  /// the same file, minus its contents, for once they're no longer needed
  PickedFile get withoutBytes => PickedFile(name: name, size: size, path: path);
}

class FileService {
  const FileService();

  Future<List<PickedFile>> pickFiles({bool allowMultiple = true}) =>
      platform.pickFiles(allowMultiple: allowMultiple);

  /// the path written on native, or null on web where the browser owns the
  /// download. null also means the dialog was cancelled
  Future<String?> saveBytes({
    required String suggestedName,
    required Uint8List bytes,
  }) => platform.saveBytes(suggestedName: suggestedName, bytes: bytes);

  /// asks where a streaming job should write, without writing anything yet
  Future<String?> chooseSavePath({required String suggestedName}) =>
      platform.chooseSavePath(suggestedName: suggestedName);

  bool get canStreamToDisk => platform.canStreamToDisk;
}

/// wraps a subtree so files dropped on it come back as a list
class FileDropTarget extends StatelessWidget {
  const FileDropTarget({
    required this.child,
    required this.onFiles,
    this.onDragChanged,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ValueChanged<List<PickedFile>> onFiles;
  final ValueChanged<bool>? onDragChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DropTarget(
      onDragEntered: (_) => onDragChanged?.call(true),
      onDragExited: (_) => onDragChanged?.call(false),
      onDragDone: (details) async {
        onDragChanged?.call(false);
        final files = <PickedFile>[];
        for (final file in details.files) {
          final length = await file.length();
          files.add(
            PickedFile(
              name: file.name,
              size: length,
              path: platform.canStreamToDisk ? file.path : null,
              bytes: platform.canStreamToDisk ? null : await file.readAsBytes(),
            ),
          );
        }
        if (files.isNotEmpty) onFiles(files);
      },
      child: child,
    );
  }
}

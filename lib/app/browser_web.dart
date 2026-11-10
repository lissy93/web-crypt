import 'dart:js_interop';
import 'dart:ui';

import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;
import 'package:web_crypt/core/utils/log.dart';
import 'package:web_crypt/services/file_service.dart';

const _log = Log('browser');

/// path urls rather than `#/encrypt`, so `/keys` deep links straight in
void useCleanUrls() => usePathUrlStrategy();

/// the browser bar follows the in-app theme, not just the system one
void setPageTheme(Color background, Brightness brightness) {
  final rgb = (background.toARGB32() & 0xffffff).toRadixString(16);
  final metas = web.document.querySelectorAll('meta[name="theme-color"]');
  for (var i = 0; i < metas.length; i++) {
    (metas.item(i)! as web.Element)
      ..removeAttribute('media')
      ..setAttribute('content', '#${rgb.padLeft(6, '0')}');
  }
  final root = web.document.documentElement! as web.HTMLElement;
  root.style.colorScheme = brightness.name;
}

@JS('launchQueue')
external _LaunchQueue? get _launchQueue;

extension type _LaunchQueue._(JSObject _) implements JSObject {
  external void setConsumer(JSFunction consumer);
}

extension type _LaunchParams._(JSObject _) implements JSObject {
  external String? get targetURL;
  // missing where launches are handled but files are not
  external JSArray<web.FileSystemFileHandle>? get files;
}

/// shortcut and file launches of the installed app, see manifest.json
void onLaunch(void Function(String route, PickedFile? file) launch) {
  _launchQueue?.setConsumer(
    ((_LaunchParams params) {
      _handle(params, launch);
    }).toJS,
  );
}

// focus-existing keeps the open window as it was, so this moves it along
Future<void> _handle(
  _LaunchParams params,
  void Function(String route, PickedFile? file) launch,
) async {
  final route = _route(params);
  final handles = params.files?.toDart ?? const [];
  if (handles.isEmpty) return launch(route, null);
  try {
    final file = await handles.first.getFile().toDart;
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    launch(route, PickedFile(name: file.name, size: file.size, bytes: bytes));
  } on Object catch (error) {
    _log.warn('could not read a file opened from the OS', error);
  }
}

/// the launch's page, without the base href, as the router knows it
String _route(_LaunchParams params) {
  final base = Uri.parse(web.document.baseURI).path;
  final path = Uri.tryParse(params.targetURL ?? '')?.path ?? '';
  return path.startsWith(base) ? '/${path.substring(base.length)}' : '/';
}

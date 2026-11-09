import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_crypt/app/app.dart';
import 'package:web_crypt/app/providers.dart';
import 'package:web_crypt/app/url_strategy_stub.dart'
    if (dart.library.js_interop) 'package:web_crypt/app/url_strategy_web.dart';
import 'package:web_crypt/core/utils/log.dart';
import 'package:web_crypt/services/storage_service.dart';

const _log = Log('app');

const _fontLicences = {
  'Inter': 'assets/fonts/Inter-LICENSE.txt',
  'JetBrains Mono': 'assets/fonts/JetBrainsMono-LICENSE.txt',
};

/// Flutter only collects licences from packages, and the OFL asks that its
/// text ships with the fonts, so the bundled families go in by hand
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in _fontLicences.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  useCleanUrls();
  registerFontLicences();

  FlutterError.onError = (details) {
    _log.error('uncaught framework error', details.exception);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.error('uncaught async error', error, stack);
    return true;
  };

  final storage = await StorageService.create();
  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const WebCryptApp(),
    ),
  );
}

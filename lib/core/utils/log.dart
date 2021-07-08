import 'dart:developer' as developer;

enum LogLevel { debug, info, warn, error }

const _releaseMode = bool.fromEnvironment('dart.vm.product');

/// never pass key material, passphrases, plaintext or chosen file names in
/// here, only shapes and counts
class Log {
  const Log(this._name);

  final String _name;

  void debug(String message) => _write(LogLevel.debug, message);

  void info(String message) => _write(LogLevel.info, message);

  void warn(String message, [Object? error]) =>
      _write(LogLevel.warn, message, error);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _write(LogLevel.error, message, error, stackTrace);

  void _write(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_releaseMode && level.index < LogLevel.warn.index) return;
    developer.log(
      message,
      name: _name,
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      },
      // only the runtime type, so a library cannot leak secrets through here
      error: error?.runtimeType.toString(),
      stackTrace: _releaseMode ? null : stackTrace,
    );
  }
}

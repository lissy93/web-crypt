library age.src;

import 'dart:async';

/// Splits an age file into its ASCII header and its binary payload.
///
/// Closes the header at the MAC line and passes pause and resume through to
/// the source, so the payload streams rather than buffering.
class AgeStream {
  AgeStream(Stream<List<int>> content) {
    payload = StreamController<List<int>>(
      onListen: _resume,
      onPause: () => _subscription.pause(),
      onResume: _resume,
      onCancel: () => _subscription.cancel(),
    );
    _subscription = content.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: false,
    );
  }

  final header = StreamController<List<int>>();
  late final StreamController<List<int>> payload;
  late final StreamSubscription<List<int>> _subscription;

  bool _inPayload = false;
  bool _inMacLine = false;
  int _dashRun = 0;

  void _onData(List<int> bytes) {
    if (_inPayload) {
      payload.add(bytes);
      return;
    }

    final headerBytes = <int>[];
    var payloadStart = bytes.length;
    for (var i = 0; i < bytes.length; i++) {
      final byte = bytes[i];
      if (!_inMacLine) {
        // Looking for a newline followed by three dashes.
        if (byte == 0x0a) {
          _dashRun = 1;
        } else if (byte == 0x2d && _dashRun > 0) {
          _dashRun++;
        } else if (_dashRun != 0) {
          _dashRun = 0;
        }
        if (_dashRun == 4) _inMacLine = true;
        headerBytes.add(byte);
      } else if (byte == 0x0a) {
        _inPayload = true;
        payloadStart = i + 1;
        break;
      } else {
        headerBytes.add(byte);
      }
    }

    if (headerBytes.isNotEmpty) header.add(headerBytes);
    if (!_inPayload) return;

    header.close();
    if (payloadStart < bytes.length) {
      payload.add(bytes.sublist(payloadStart));
    }
    // Hold the source until somebody is actually reading the payload.
    if (!payload.hasListener) _subscription.pause();
  }

  void _onDone() {
    if (!_inPayload) {
      header.addError(Exception('Mac line not found in header!'));
      header.close();
    }
    payload.close();
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!header.isClosed) header.addError(error, stackTrace);
    payload.addError(error, stackTrace);
  }

  void _resume() {
    if (_subscription.isPaused) _subscription.resume();
  }
}

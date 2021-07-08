import 'dart:async';
import 'dart:typed_data';

class HeadedStream {
  const HeadedStream(this.head, this.stream);

  final Uint8List head;

  /// the whole thing, [head] included
  final Stream<List<int>> stream;
}

/// reads up to [size] bytes for sniffing, and still hands back a stream that
/// starts from byte zero
Future<HeadedStream> peekHead(Stream<List<int>> input, int size) async {
  final head = BytesBuilder(copy: false);
  final queue = StreamController<List<int>>();
  final completer = Completer<void>();
  var forwarding = false;

  late final StreamSubscription<List<int>> subscription;
  subscription = input.listen(
    (chunk) {
      if (forwarding) {
        queue.add(chunk);
        return;
      }
      final need = size - head.length;
      if (chunk.length <= need) {
        head.add(chunk);
      } else {
        head.add(chunk.sublist(0, need));
        queue.add(chunk.sublist(need));
      }
      if (head.length >= size) {
        forwarding = true;
        subscription.pause();
        if (!completer.isCompleted) completer.complete();
      }
    },
    onError: (Object error, StackTrace trace) {
      queue.addError(error, trace);
      if (!completer.isCompleted) completer.complete();
    },
    onDone: () {
      forwarding = true;
      queue.close();
      if (!completer.isCompleted) completer.complete();
    },
    cancelOnError: false,
  );

  queue
    ..onListen = () {
      if (subscription.isPaused) subscription.resume();
    }
    ..onPause = subscription.pause
    ..onResume = () {
      if (subscription.isPaused) subscription.resume();
    }
    ..onCancel = subscription.cancel;

  await completer.future;
  final headBytes = head.takeBytes();
  return HeadedStream(headBytes, _prepend(headBytes, queue.stream));
}

Stream<List<int>> _prepend(Uint8List head, Stream<List<int>> rest) async* {
  if (head.isNotEmpty) yield head;
  yield* rest;
}

Future<Uint8List> collectBytes(Stream<List<int>> input) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in input) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// reports every [every] bytes, plus once at the end
Stream<List<int>> countingBytes(
  Stream<List<int>> source,
  void Function(int processed) onProgress, {
  int every = 256 * 1024,
}) async* {
  var processed = 0;
  var reported = 0;
  await for (final chunk in source) {
    processed += chunk.length;
    if (processed - reported >= every) {
      reported = processed;
      onProgress(processed);
    }
    yield chunk;
  }
  if (processed != reported) onProgress(processed);
}

/// lets long loops pause now and then, so a web page can still paint
class Pacer {
  final _clock = Stopwatch()..start();

  bool get due => _clock.elapsedMilliseconds >= 50;

  /// a timer rather than a microtask, which would not let the page in
  Future<void> rest() async {
    await Future<void>.delayed(Duration.zero);
    _clock.reset();
  }
}

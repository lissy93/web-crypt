import 'package:flutter_web_plugins/url_strategy.dart';

/// path urls rather than `#/encrypt`, so `/keys` deep links straight in
void useCleanUrls() => usePathUrlStrategy();

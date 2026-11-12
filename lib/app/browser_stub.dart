import 'dart:ui';

import 'package:web_crypt/services/file_service.dart';

/// native has no urls to configure
void useCleanUrls() {}

/// native windows draw their own frame
void setPageTheme(Color background, Brightness brightness) {}

/// only an installed web app is launched this way
void onLaunch(void Function(String route, PickedFile? file) launch) {}

{{flutter_js}}
{{flutter_build_config}}

// keeps glyph fallbacks local, the engine appends its own path after the "?"
_flutter.loader.load({
  config: { fontFallbackBaseUrl: "assets/fonts/MaterialIcons-Regular.otf?" },
});

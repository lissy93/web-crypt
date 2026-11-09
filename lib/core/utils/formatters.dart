const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 100 || value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$rounded ${_units[unit]}';
}

/// `AABBCCDD...` becomes `AABB CCDD ...`, the way key tools print them
String groupFingerprint(String hex, {int groupSize = 4}) {
  final upper = hex.toUpperCase();
  final groups = <String>[];
  for (var i = 0; i < upper.length; i += groupSize) {
    groups.add(upper.substring(i, (i + groupSize).clamp(0, upper.length)));
  }
  return groups.join(' ');
}

String shortFingerprint(String fingerprint) {
  final trimmed = fingerprint.replaceAll(' ', '');
  if (trimmed.length <= 16) return trimmed;
  return trimmed.substring(trimmed.length - 16);
}

String formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// middle-truncates so both ends stay readable
String ellipsise(String value, int max) {
  if (value.length <= max) return value;
  final keep = (max - 1) ~/ 2;
  return '${value.substring(0, keep)}…${value.substring(value.length - keep)}';
}

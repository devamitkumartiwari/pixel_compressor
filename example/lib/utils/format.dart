String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  double value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[unitIndex]}';
}

String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  final millis = duration.inMilliseconds;
  if (millis < 1000) return '${millis}ms';
  return '${(millis / 1000).toStringAsFixed(2)}s';
}

/// `mm:ss` for a position inside a video, e.g. thumbnail or trim labels.
String formatTimestamp(Duration position) {
  final m = position.inMinutes.toString().padLeft(2, '0');
  final s = (position.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

String formatBitrate(int bps) {
  if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  return '${(bps / 1000).round()} kbps';
}

/// Plain-language meaning of an EXIF orientation value (1–8).
String describeOrientation(int orientation) => switch (orientation) {
  1 => 'Upright',
  2 => 'Mirrored horizontally',
  3 => 'Rotated 180°',
  4 => 'Mirrored vertically',
  5 => 'Mirrored + rotated 90° CCW',
  6 => 'Rotated 90° CW',
  7 => 'Mirrored + rotated 90° CW',
  8 => 'Rotated 90° CCW',
  _ => 'Unknown',
};

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

String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

import 'dart:math';

int _counter = 0;
final Random _random = Random();

/// A unique-enough-per-session id for tagging a compression task across the
/// request, its progress stream, and cancellation — not a UUID, just needs
/// to be unique within one app run.
String generateTaskId(String prefix) {
  _counter += 1;
  final salt = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter$salt';
}

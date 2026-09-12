import 'dart:typed_data';

import 'exceptions/pixel_compressor_exception.dart';
import 'target_size_constants.dart';

/// One `targetSizeBytes` attempt's outcome, fed back into
/// [runTargetSizeLoop] to decide the next step.
class TargetSizeAttempt {
  const TargetSizeAttempt({required this.bytes, required this.longestEdge});

  final Uint8List bytes;
  final int longestEdge;
}

/// Re-runs [attempt] at decreasing quality, then decreasing resolution,
/// until its output is at or under [targetSizeBytes] or the shared attempt
/// budget ([kTargetSizeMaxAttempts]) is exhausted — the same
/// quality-then-resolution stepping algorithm the native Android/iOS image
/// engines use, with the same constants, so `targetSizeBytes` behaves
/// consistently everywhere this plugin runs.
///
/// [attempt] receives the quality (1-100) and an optional max-longest-edge
/// constraint (`null` on the first call, meaning "use the caller's own
/// requested size") and returns the encoded bytes plus the resulting
/// longest edge. [onAttempt], if given, is called after every attempt with
/// a 1-based attempt number and a human-readable note (for progress
/// reporting).
Future<Uint8List> runTargetSizeLoop({
  required int targetSizeBytes,
  required Future<TargetSizeAttempt> Function(int quality, int? maxLongestEdge)
  attempt,
  void Function(int attemptNumber, int maxAttempts, String note)? onAttempt,
}) async {
  var quality = kTargetSizeInitialQuality;
  int? maxLongestEdge;
  Uint8List? lastBytes;

  for (
    var attemptNumber = 1;
    attemptNumber <= kTargetSizeMaxAttempts;
    attemptNumber++
  ) {
    final result = await attempt(quality, maxLongestEdge);
    lastBytes = result.bytes;
    onAttempt?.call(
      attemptNumber,
      kTargetSizeMaxAttempts,
      'attempt $attemptNumber/$kTargetSizeMaxAttempts quality=$quality edge=${result.longestEdge}',
    );

    if (result.bytes.lengthInBytes <= targetSizeBytes) {
      return result.bytes;
    }
    if (attemptNumber >= kTargetSizeMaxAttempts) break;

    if (quality > kTargetSizeQualityFloor) {
      quality = (quality - kTargetSizeQualityStep).clamp(
        kTargetSizeQualityFloor,
        100,
      );
    } else {
      final newEdge = (result.longestEdge * kTargetSizeResolutionStepFactor)
          .round();
      maxLongestEdge = newEdge < kTargetSizeMinEdgePx
          ? kTargetSizeMinEdgePx
          : newEdge;
    }
  }

  throw TargetSizeException(
    nativeCode: 'target_size_unachievable',
    nativeMessage:
        'Could not reach target size of $targetSizeBytes bytes after '
        '$kTargetSizeMaxAttempts attempts (best attempt: '
        '${lastBytes?.lengthInBytes ?? 0} bytes)',
  );
}

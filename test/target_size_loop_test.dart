import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:pixel_compressor/src/core/target_size_loop.dart';

void main() {
  test('returns the first attempt that already fits', () async {
    var calls = 0;
    final bytes = await runTargetSizeLoop(
      targetSizeBytes: 100,
      attempt: (quality, maxLongestEdge) async {
        calls++;
        return TargetSizeAttempt(bytes: Uint8List(50), longestEdge: 500);
      },
    );
    expect(bytes.lengthInBytes, 50);
    expect(calls, 1);
  });

  test('steps quality down before touching resolution', () async {
    final qualitiesSeen = <int>[];
    await runTargetSizeLoop(
      targetSizeBytes: 10,
      attempt: (quality, maxLongestEdge) async {
        qualitiesSeen.add(quality);
        // Never satisfied until the floor is hit on the 6th attempt
        // (90, 75, 60, 45, 30, 15 -> floor 10 on attempt 7).
        final satisfied = quality <= 15;
        return TargetSizeAttempt(
          bytes: Uint8List(satisfied ? 5 : 1000),
          longestEdge: 1000,
        );
      },
    );
    // Quality steps by 15 from the initial 90, floored at 10, before any
    // maxLongestEdge constraint is ever introduced.
    expect(qualitiesSeen, [90, 75, 60, 45, 30, 15]);
  });

  test('steps resolution down once quality hits its floor', () async {
    final edgesRequested = <int?>[];
    await runTargetSizeLoop(
      targetSizeBytes: 10,
      attempt: (quality, maxLongestEdge) async {
        edgesRequested.add(maxLongestEdge);
        // Never satisfied at full quality; once quality bottoms out,
        // satisfy on the first resolution-constrained attempt.
        final satisfied = quality <= 10 && maxLongestEdge != null;
        return TargetSizeAttempt(
          bytes: Uint8List(satisfied ? 5 : 1000),
          longestEdge: maxLongestEdge ?? 1000,
        );
      },
    );
    // Quality steps 90,75,60,45,30,15,10 (7 attempts, floor reached on the
    // 7th) all with no edge constraint; only once quality is AT the floor
    // and still unsatisfied does the 8th attempt introduce one, stepped
    // down by 0.75 from the longestEdge the 7th attempt reported (1000 ->
    // 750).
    expect(edgesRequested.take(7), everyElement(isNull));
    expect(edgesRequested.length, 8);
    expect(edgesRequested.last, 750);
  });

  test(
    'throws TargetSizeException after exhausting the attempt budget',
    () async {
      await expectLater(
        runTargetSizeLoop(
          targetSizeBytes: 1,
          attempt: (quality, maxLongestEdge) async =>
              TargetSizeAttempt(bytes: Uint8List(1000), longestEdge: 1000),
        ),
        throwsA(isA<TargetSizeException>()),
      );
    },
  );

  test(
    'reports one onAttempt call per attempt with an increasing number',
    () async {
      final attemptNumbers = <int>[];
      await runTargetSizeLoop(
        targetSizeBytes: 100,
        attempt: (quality, maxLongestEdge) async => TargetSizeAttempt(
          bytes: Uint8List(quality == 90 ? 1000 : 50),
          longestEdge: 500,
        ),
        onAttempt: (attemptNumber, maxAttempts, note) {
          attemptNumbers.add(attemptNumber);
          expect(maxAttempts, 8);
        },
      );
      expect(attemptNumbers, [1, 2]);
    },
  );
}

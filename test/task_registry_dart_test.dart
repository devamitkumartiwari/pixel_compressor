import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/src/platform/task_registry_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Each test starts from a clean slate — drain anything a previous
    // test (or a previous run's failure) left registered.
    for (final id in List.of(TaskRegistryDart.instance.activeTaskIds)) {
      TaskRegistryDart.instance.unregister(id);
    }
  });

  test('activeTaskIds reflects both Dart and native registrations, pure bookkeeping', () {
    final registry = TaskRegistryDart.instance;
    expect(registry.activeTaskIds, isEmpty);

    registry.registerDart('dart-1');
    registry.registerNative('native-1');
    expect(registry.activeTaskIds, unorderedEquals(['dart-1', 'native-1']));

    registry.unregister('dart-1');
    expect(registry.activeTaskIds, ['native-1']);

    registry.unregister('native-1');
    expect(registry.activeTaskIds, isEmpty);
  });

  test('cancel() on a Dart-run task flips its token and returns true, no channel touched', () async {
    final registry = TaskRegistryDart.instance;
    final token = registry.registerDart('dart-2');

    final cancelled = await registry.cancel('dart-2');

    expect(cancelled, isTrue);
    expect(token.isCancelled, isTrue);
    registry.unregister('dart-2');
  });

  test('cancel() on an unknown task id returns false', () async {
    expect(await TaskRegistryDart.instance.cancel('does-not-exist'), isFalse);
  });

  test(
    'cancel() on a native-run task attempts a real platform channel call',
    () async {
      final registry = TaskRegistryDart.instance;
      registry.registerNative('native-2');

      // No native plugin is registered in this test environment, so
      // forwarding to the real TaskHostApi channel must fail loudly rather
      // than silently succeed — proving this path genuinely reaches native
      // instead of being answered from Dart bookkeeping alone.
      await expectLater(registry.cancel('native-2'), throwsA(anything));

      registry.unregister('native-2');
    },
  );

  test('cancelAll() cancels every Dart token without touching native when none are registered', () async {
    final registry = TaskRegistryDart.instance;
    final tokenA = registry.registerDart('dart-3');
    final tokenB = registry.registerDart('dart-4');

    // Must complete without throwing — if this unconditionally called the
    // native cancelAll() channel (unregistered in this test environment),
    // it would throw, which is exactly the web-safety bug this guards.
    await expectLater(registry.cancelAll(), completes);

    expect(tokenA.isCancelled, isTrue);
    expect(tokenB.isCancelled, isTrue);
    registry.unregister('dart-3');
    registry.unregister('dart-4');
  });

  test(
    'cancelAll() with a native task registered attempts the native channel',
    () async {
      final registry = TaskRegistryDart.instance;
      registry.registerNative('native-3');

      await expectLater(registry.cancelAll(), throwsA(anything));

      registry.unregister('native-3');
    },
  );
}

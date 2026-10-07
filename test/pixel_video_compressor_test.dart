import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_compressor/pixel_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pixel_compressor/video');
  final calls = <MethodCall>[];
  final info = {
    'path': '/tmp/out.mp4',
    'title': '',
    'author': '',
    'width': 1280,
    'height': 720,
    'duration': 1500,
    'filesize': 1024,
    'isCancel': false,
  };

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'compressVideo':
            case 'getMediaInfo':
              return jsonEncode(info);
            case 'getByteThumbnail':
              return Uint8List.fromList([1, 2]);
            case 'getFileThumbnail':
              return '/tmp/thumb.jpg';
            case 'deleteAllCache':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('compressVideoFile sends compressVideo with base args', () async {
    final result = await PixelVideoCompressor.compressVideoFile(
      '/tmp/in.mp4',
      quality: PixelVideoQuality.Res1280x720Quality,
      startTime: 2,
      duration: 5,
      includeAudio: false,
    );
    expect(calls.single.method, 'compressVideo');
    expect(calls.single.arguments, {
      'path': '/tmp/in.mp4',
      'quality': 6,
      'deleteOrigin': false,
      'startTime': 2,
      'duration': 5,
      'includeAudio': false,
      'frameRate': 30,
      'codec': 'h264',
      'keyFrameInterval': 3.0,
      'preventLargerOutput': true,
    });
    expect(result?.width, 1280);
    expect(result?.duration, 1500);
    expect(result?.isCancel, false);
    expect(PixelVideoCompressor.isCompressing, isFalse);
  });

  test('readMediaInfo parses the JSON reply', () async {
    final result = await PixelVideoCompressor.readMediaInfo('/tmp/in.mp4');
    expect(calls.single.method, 'getMediaInfo');
    expect(result.height, 720);
    expect(result.filesize, 1024);
  });

  test('thumbnails map to native method names', () async {
    final bytes = await PixelVideoCompressor.thumbnailBytes(
      '/tmp/in.mp4',
      quality: 50,
      position: 1000,
    );
    final file = await PixelVideoCompressor.thumbnailFile('/tmp/in.mp4');
    expect(bytes, [1, 2]);
    expect(file, isA<XFile>());
    expect(file.path, '/tmp/thumb.jpg');
    expect(calls.map((c) => c.method), [
      'getByteThumbnail',
      'getFileThumbnail',
    ]);
    expect(calls.first.arguments, {
      'path': '/tmp/in.mp4',
      'quality': 50,
      'position': 1000,
      'maxSize': 512,
    });
  });

  test('cancel, cache and log level map to native method names', () async {
    await PixelVideoCompressor.cancelVideoCompression();
    expect(await PixelVideoCompressor.clearVideoCache(), isTrue);
    await PixelVideoCompressor.setNativeLogLevel(2);
    expect(calls.map((c) => c.method), [
      'cancelCompression',
      'deleteAllCache',
      'setLogLevel',
    ]);
    expect(calls.last.arguments, {'logLevel': 2});
  });

  test('native updateProgress events reach progress\$', () async {
    final events = <double>[];
    final sub = PixelVideoCompressor.progress$.subscribe(events.add);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('updateProgress', 42.5),
          ),
          (_) {},
        );
    await Future<void>.delayed(.zero);
    expect(events, [42.5]);
    sub.unsubscribe();
  });

  test('progress\$ supports several independent subscribers', () async {
    final a = <double>[];
    final b = <double>[];
    final subA = PixelVideoCompressor.progress$.subscribe(a.add);
    final subB = PixelVideoCompressor.progress$.subscribe(b.add);
    Future<void> emit(double v) => TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('updateProgress', v)),
          (_) {},
        );
    await emit(10);
    await Future<void>.delayed(.zero);
    subA.unsubscribe();
    await emit(20);
    await Future<void>.delayed(.zero);
    subB.unsubscribe();
    expect(a, [10]);
    expect(b, [10, 20]);
    expect(PixelVideoCompressor.progress$.notSubscribed, isTrue);
  });

  test('thumbnailFile keeps paths with % and spaces intact', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => '/tmp/100% done_0.jpg',
        );
    final file = await PixelVideoCompressor.thumbnailFile('/tmp/in.mp4');
    expect(file.path, '/tmp/100% done_0.jpg');
  });

  test('PixelMediaInfo.fromJson wraps the path in an XFile', () {
    final withPath = PixelMediaInfo.fromJson({'path': '/tmp/a.mp4'});
    expect(withPath.file, isA<XFile>());
    expect(withPath.file!.path, '/tmp/a.mp4');
    expect(withPath.toJson()['file'], '/tmp/a.mp4');

    final noPath = PixelMediaInfo.fromJson({'path': null});
    expect(noPath.file, isNull);
  });
}

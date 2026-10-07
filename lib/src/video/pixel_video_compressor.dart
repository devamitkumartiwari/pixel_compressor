import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'compress_mixin.dart';
import 'media_info.dart';
import 'video_quality.dart';

abstract class IPixelVideoCompressor() extends PixelVideoCompressMixin {}

class _PixelVideoCompressorImpl._() extends IPixelVideoCompressor {
  this {
    initProcessCallback();
  }

  static _PixelVideoCompressorImpl? _instance;

  static _PixelVideoCompressorImpl get instance {
    return _instance ??= _PixelVideoCompressorImpl._();
  }

  static void _dispose() {
    _instance = null;
  }
}

// ignore: non_constant_identifier_names
IPixelVideoCompressor get PixelVideoCompressor =>
    _PixelVideoCompressorImpl.instance;

extension PixelVideoCompress on IPixelVideoCompressor {
  void dispose() {
    _PixelVideoCompressorImpl._dispose();
  }

  Future<T?> _invoke<T>(String name, [Map<String, dynamic>? params]) async {
    T? result;
    try {
      result = params != null
          ? await channel.invokeMethod(name, params)
          : await channel.invokeMethod(name);
    } on PlatformException catch (e) {
      debugPrint('''Error from PixelVideoCompressor:
      Method: $name
      $e''');
    }
    return result;
  }

  /// thumbnailBytes return [Future<Uint8List>],
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  /// the longer side is scaled down to at most [maxSize] pixels
  Future<Uint8List?> thumbnailBytes(
    String path, {
    int quality = 100,
    int position = -1,
    int maxSize = 512,
  }) async {
    assert(quality > 1 || quality < 100);

    return await _invoke<Uint8List>('getByteThumbnail', {
      'path': path,
      'quality': quality,
      'position': position,
      'maxSize': maxSize,
    });
  }

  /// Returns the thumbnail as a [XFile] (use `File(file.path)` where a
  /// `dart:io` `File` is needed).
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  /// the longer side is scaled down to at most [maxSize] pixels
  Future<XFile> thumbnailFile(
    String path, {
    int quality = 100,
    int position = -1,
    int maxSize = 512,
  }) async {
    assert(quality > 1 || quality < 100);

    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final filePath = await (_invoke<String>('getFileThumbnail', {
      'path': path,
      'quality': quality,
      'position': position,
      'maxSize': maxSize,
    }));

    // Native returns a plain file-system path; decoding it again broke names
    // containing '%'.
    return XFile(filePath!);
  }

  /// get media information from [path]
  ///
  /// get media information from [path] return [Future<PixelMediaInfo>]
  ///
  /// ## example
  /// ```dart
  /// final info = await PixelVideoCompressor.readMediaInfo(file.path);
  /// debugPrint(info.toJson());
  /// ```
  Future<PixelMediaInfo> readMediaInfo(String path) async {
    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final jsonStr = await (_invoke<String>('getMediaInfo', {'path': path}));
    final jsonMap = json.decode(jsonStr!);
    return PixelMediaInfo.fromJson(jsonMap);
  }

  /// compress video from [path]
  /// compress video from [path] return [Future<PixelMediaInfo>]
  ///
  /// you can choose its quality by [quality],
  /// determine whether to delete his source file by [deleteOrigin]
  /// optional parameters [startTime] [duration] (seconds) [includeAudio]
  /// [frameRate]
  ///
  /// pixel_compressor options:
  /// * [bitrate]: target average video bitrate in bits per second, used as
  ///   given. Without it the bitrate is derived from the output size and
  ///   capped below the source's, so the output never grows.
  /// * [maxWidth] / [maxHeight]: fit the (display-oriented) output inside
  ///   this box, keeping the aspect ratio and never upscaling. Overrides the
  ///   size implied by [quality].
  /// * [codec]: H.264 (default) or HEVC.
  /// * [keyFrameInterval]: seconds between key frames (default 3).
  /// * [audioBitrate], [audioSampleRate] (8–48 kHz) and [audioChannels]
  ///   (1 or 2): AAC output settings. Defaults: 128 kbps (64 kbps mono), the
  ///   source's sample rate capped at 48 kHz and channels capped at 2. When
  ///   none is set, Android keeps an AAC source track without re-encoding.
  /// * [preventLargerOutput] (default true): cap the derived bitrate below
  ///   the source's and, if the result is still larger, keep the original
  ///   streams. Only applies when no [bitrate], size or trim is requested.
  /// * [outputPath]: where to write the MP4 (must end in `.mp4`); parent
  ///   directories are created and an existing file is replaced. Defaults
  ///   to the plugin's cache directory.
  ///
  /// ## example
  /// ```dart
  /// final info = await PixelVideoCompressor.compressVideoFile(
  ///   file.path,
  ///   deleteOrigin: true,
  /// );
  /// debugPrint(info.toJson());
  /// ```
  Future<PixelMediaInfo?> compressVideoFile(
    String path, {
    PixelVideoQuality quality = PixelVideoQuality.DefaultQuality,
    bool deleteOrigin = false,
    int? startTime,
    int? duration,
    bool? includeAudio,
    int frameRate = 30,
    int? bitrate,
    int? maxWidth,
    int? maxHeight,
    String? outputPath,
    PixelVideoCodec codec = .h264,
    double keyFrameInterval = 3,
    int? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    bool preventLargerOutput = true,
  }) async {
    if (keyFrameInterval <= 0) {
      throw ArgumentError.value(
        keyFrameInterval,
        'keyFrameInterval',
        'must be > 0',
      );
    }
    if (audioBitrate != null && audioBitrate <= 0) {
      throw ArgumentError.value(audioBitrate, 'audioBitrate', 'must be > 0');
    }
    if (audioSampleRate != null &&
        (audioSampleRate < 8000 || audioSampleRate > 48000)) {
      throw ArgumentError.value(
        audioSampleRate,
        'audioSampleRate',
        'must be 8000–48000',
      );
    }
    if (audioChannels != null && audioChannels != 1 && audioChannels != 2) {
      throw ArgumentError.value(
        audioChannels,
        'audioChannels',
        'must be 1 or 2',
      );
    }
    if (bitrate != null && bitrate <= 0) {
      throw ArgumentError.value(bitrate, 'bitrate', 'must be > 0');
    }
    if (maxWidth != null && maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'must be > 0');
    }
    if (maxHeight != null && maxHeight <= 0) {
      throw ArgumentError.value(maxHeight, 'maxHeight', 'must be > 0');
    }
    if (outputPath != null && !outputPath.toLowerCase().endsWith('.mp4')) {
      throw ArgumentError.value(outputPath, 'outputPath', 'must end in .mp4');
    }
    if (outputPath != null && _normalized(outputPath) == _normalized(path)) {
      throw ArgumentError.value(
        outputPath,
        'outputPath',
        'must differ from the source path',
      );
    }
    if (isCompressing) {
      throw StateError(
        '''PixelVideoCompressor Error:
      Method: compressVideoFile
      Already have a compression process, you need to wait for the process to finish or stop it''',
      );
    }

    if (progress$.notSubscribed) {
      debugPrint('''PixelVideoCompressor: You can try to subscribe to the
      progress\$ stream to know the compressing state.''');
    }

    // ignore: invalid_use_of_protected_member
    setProcessingStatus(true);
    final String? jsonStr;
    try {
      jsonStr = await _invoke<String>('compressVideo', {
        'path': path,
        'quality': quality.index,
        'deleteOrigin': deleteOrigin,
        'startTime': startTime,
        'duration': duration,
        'includeAudio': includeAudio,
        'frameRate': frameRate,
        'bitrate': ?bitrate,
        'maxWidth': ?maxWidth,
        'maxHeight': ?maxHeight,
        'outputPath': ?outputPath,
        'codec': codec.name,
        'keyFrameInterval': keyFrameInterval,
        'audioBitrate': ?audioBitrate,
        'audioSampleRate': ?audioSampleRate,
        'audioChannels': ?audioChannels,
        'preventLargerOutput': preventLargerOutput,
      });
    } finally {
      // ignore: invalid_use_of_protected_member
      setProcessingStatus(false);
    }

    if (jsonStr != null) {
      final jsonMap = json.decode(jsonStr);
      return PixelMediaInfo.fromJson(jsonMap);
    } else {
      return null;
    }
  }

  /// stop compressing the file that is currently being compressed.
  /// If there is no compression process, nothing will happen.
  Future<void> cancelVideoCompression() async {
    await _invoke<void>('cancelCompression');
  }

  /// delete the cache folder, please do not put other things
  /// in the folder of this plugin, it will be cleared
  Future<bool?> clearVideoCache() async {
    return await _invoke<bool>('deleteAllCache');
  }

  Future<void> setNativeLogLevel(int logLevel) async {
    return await _invoke<void>('setLogLevel', {'logLevel': logLevel});
  }
}

/// [path] with `.` and `..` segments resolved, for same-file checks.
String _normalized(String path) => Uri.file(path).normalizePath().toFilePath();

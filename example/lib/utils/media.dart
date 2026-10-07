import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pixel_compressor/pixel_compressor.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'web_file_picker.dart';

/// A bundled, license-free sample image (generated, see `assets/samples/`).
class const Sample(this.asset, this.label, this.description) {
  final String asset;
  final String label;
  final String description;

  String get name => asset.split('/').last;
}

const samples = [
  Sample('assets/samples/landscape.jpg', 'Landscape', '2400×1600 JPEG'),
  Sample(
    'assets/samples/portrait_exif6.jpg',
    'Portrait (EXIF 6)',
    'Stored sideways, EXIF says rotate 90°',
  ),
  Sample('assets/samples/square.png', 'Square', '1200×1200 PNG, transparent'),
];

/// An input image with its bytes always loaded (for previews and sizes),
/// plus where it came from: a file [path] (native pickers) or an [asset].
class const PickedImage({
  required this.name,
  required this.bytes,
  this.path,
  this.asset,
}) {
  final String name;
  final Uint8List bytes;
  final String? path;
  final String? asset;

  int get size => bytes.length;

  static Future<PickedImage> fromSample(Sample sample) async {
    final data = await rootBundle.load(sample.asset);
    return PickedImage(
      name: sample.name,
      bytes: data.buffer.asUint8List(),
      asset: sample.asset,
    );
  }

  /// The original file behind a gallery [asset], or null when it can't be
  /// read (e.g. an iCloud item that failed to download).
  static Future<PickedImage?> fromAssetEntity(AssetEntity asset) async {
    final file = await asset.originFile;
    if (file == null) return null;
    return PickedImage(
      name: await asset.titleAsync,
      bytes: await file.readAsBytes(),
      path: file.path,
    );
  }

  /// A file picked in the browser (bytes only; there is no path on the web).
  factory PickedImage.fromWeb(WebPickedFile file) =>
      PickedImage(name: file.name, bytes: file.bytes);
}

/// Scratch directory for everything the example writes.
Future<Directory> exampleTempDir() async {
  final dir = Directory(
    '${Directory.systemTemp.path}/pixel_compressor_example',
  );
  await dir.create(recursive: true);
  return dir;
}

/// A file path for [image]: its own path, or a temp copy for assets (the
/// file-based APIs need a real file).
Future<String> materialize(PickedImage image) async {
  final path = image.path;
  if (path != null) return path;
  final file = File('${(await exampleTempDir()).path}/${image.name}');
  await file.writeAsBytes(image.bytes);
  return file.path;
}

/// File extension the validator expects for [format] in `compressFileToFile`.
String extensionFor(PixelImageFormat format) => switch (format) {
  .jpeg => 'jpg',
  .png => 'png',
  .webp => 'webp',
  .heic => 'heic',
};

/// A fresh output path in the temp directory, e.g. `landscape_1712345.jpg`.
Future<String> outputPathFor(String sourceName, String extension) async {
  final dot = sourceName.lastIndexOf('.');
  final base = dot > 0 ? sourceName.substring(0, dot) : sourceName;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return '${(await exampleTempDir()).path}/${base}_$stamp.$extension';
}

int fileSize(String path) {
  try {
    return File(path).lengthSync();
  } on FileSystemException {
    return 0;
  }
}

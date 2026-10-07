import 'dart:typed_data';

const bool mergeSupportsFiles = false;

Future<Uint8List> readMergeFile(String path) =>
    throw UnsupportedError('File sources are not available on the web');

Future<void> writeMergeFile(String path, Uint8List bytes) =>
    throw UnsupportedError('outputPath is not available on the web');

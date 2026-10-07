import 'dart:io';
import 'dart:typed_data';

const bool mergeSupportsFiles = true;

Future<Uint8List> readMergeFile(String path) => File(path).readAsBytes();

Future<void> writeMergeFile(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

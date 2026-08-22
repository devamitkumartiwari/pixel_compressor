import 'batch_item_result.dart';

/// The aggregate outcome of a batch compression job.
class BatchResult {
  const BatchResult({required this.items});

  final List<BatchItemResult> items;

  List<BatchItemResult> get succeeded =>
      items.where((i) => i.succeeded).toList();
  List<BatchItemResult> get failed => items.where((i) => !i.succeeded).toList();

  int get originalSizeBytes =>
      succeeded.fold(0, (sum, i) => sum + i.result!.originalSizeBytes);
  int get outputSizeBytes =>
      succeeded.fold(0, (sum, i) => sum + i.result!.outputSizeBytes);
  int get savedBytes => originalSizeBytes - outputSizeBytes;

  @override
  String toString() =>
      'BatchResult(${items.length} items, ${succeeded.length} succeeded, ${failed.length} failed, '
      'saved $savedBytes bytes)';
}

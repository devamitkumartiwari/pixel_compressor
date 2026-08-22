import '../../platform/messages.g.dart';
import '../../platform/wire_mapping.dart';
import '../enums/compression_stage.dart';

/// A progress update for one compression/thumbnail task, identified by
/// [taskId] so a single global stream (see `PixelCompressor.progressStream`)
/// can be filtered down to the task a caller cares about.
class ProgressEvent {
  const ProgressEvent({
    required this.taskId,
    required this.stage,
    required this.percent,
    this.currentItemIndex,
    this.totalItems,
    this.note,
  });

  factory ProgressEvent.fromMessage(ProgressEventMessage message) =>
      ProgressEvent(
        taskId: message.taskId,
        stage: message.stage.toDart(),
        percent: message.percent,
        currentItemIndex: message.currentItemIndex,
        totalItems: message.totalItems,
        note: message.note,
      );

  final String taskId;
  final CompressionStage stage;

  /// 0-100, for the current item.
  final double percent;

  /// Set only inside a batch job — this item's position (0-based).
  final int? currentItemIndex;

  /// Set only inside a batch job — total items in the batch.
  final int? totalItems;

  final String? note;

  @override
  String toString() =>
      'ProgressEvent(taskId: $taskId, stage: $stage, percent: $percent'
      '${currentItemIndex != null ? ', item: ${currentItemIndex! + 1}/$totalItems' : ''})';
}

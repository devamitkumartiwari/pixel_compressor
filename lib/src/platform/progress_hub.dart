import 'dart:async';

import '../core/models/progress_event.dart';
import 'messages.g.dart';

/// Single [PixelCompressorProgressCallbackApi] receiver for the whole app,
/// fanned out into a broadcast [Stream] filtered per task by callers — one
/// shared callback channel handles arbitrary concurrent tasks without each
/// needing its own channel lifecycle (see the `FlutterApi` note in
/// `pigeons/messages.dart`).
class ProgressHub implements PixelCompressorProgressCallbackApi {
  ProgressHub._() {
    PixelCompressorProgressCallbackApi.setUp(this);
  }

  static final ProgressHub instance = ProgressHub._();

  final StreamController<ProgressEvent> _controller =
      StreamController<ProgressEvent>.broadcast();

  Stream<ProgressEvent> get stream => _controller.stream;

  @override
  void onProgress(ProgressEventMessage event) {
    _controller.add(ProgressEvent.fromMessage(event));
  }

  @override
  void onTaskTerminal(TaskTerminalMessage message) {
    // Terminal state is delivered to callers via the compress() call's own
    // Future; this callback exists on the wire for future batch/background
    // task tracking and isn't consumed yet.
  }
}

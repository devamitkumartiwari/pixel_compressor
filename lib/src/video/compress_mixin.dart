import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'subscription.dart';

class PixelVideoCompressMixin() {
  final progress$ = PixelObservable<double>();
  final _channel = const MethodChannel('pixel_compressor/video');

  @protected
  void initProcessCallback() {
    _channel.setMethodCallHandler(_progressCallback);
  }

  MethodChannel get channel => _channel;

  bool _isCompressing = false;

  bool get isCompressing => _isCompressing;

  @protected
  void setProcessingStatus(bool status) {
    _isCompressing = status;
  }

  Future<void> _progressCallback(MethodCall call) async {
    switch (call.method) {
      case 'updateProgress':
        final progress = double.tryParse(call.arguments.toString());
        if (progress != null) progress$.next(progress);
        break;
    }
  }
}

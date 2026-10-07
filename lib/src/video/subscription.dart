import 'dart:async';

import 'dart:ui';

/// Progress stream. Broadcast, so any number of listeners can subscribe and
/// unsubscribe independently (a single-subscription controller would throw
/// "Stream has already been listened to" on the second subscriber).
class PixelObservable<T>() {
  final StreamController<T> _observable = StreamController<T>.broadcast();

  bool get notSubscribed => !_observable.hasListener;

  /// The underlying stream, for use with `StreamBuilder` or `listen`.
  Stream<T> get stream => _observable.stream;

  void next(T value) {
    _observable.add(value);
  }

  PixelProgressSubscription subscribe(
    void Function(T event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _observable.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return PixelProgressSubscription(() {
      subscription.cancel();
    });
  }
}

class const PixelProgressSubscription(this.unsubscribe) {
  final VoidCallback unsubscribe;
}

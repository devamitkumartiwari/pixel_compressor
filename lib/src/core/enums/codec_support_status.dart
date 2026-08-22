/// Whether a codec or format is available on the current device.
enum CodecSupportStatus {
  supported,
  unsupported,

  /// The native side couldn't determine support (a capability query
  /// itself failed) — treat this as "don't rely on it" rather than as an
  /// error.
  unknown,
}

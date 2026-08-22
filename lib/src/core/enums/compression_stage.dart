/// Where a compression task currently is, reported on every
/// [ProgressEvent].
enum CompressionStage {
  preparing,
  analyzing,
  decoding,
  encoding,
  muxing,
  finalizing,
  completed,
  failed,
  cancelled,
}

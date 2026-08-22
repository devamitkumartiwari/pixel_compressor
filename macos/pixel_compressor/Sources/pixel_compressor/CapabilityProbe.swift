import CoreMedia
import Foundation
import ImageIO
import VideoToolbox

/// Probes real codec support for `CapabilityHostApi`. h264/aac are always
/// supported on iOS/macOS; hevc is probed with a throwaway
/// `VTCompressionSessionCreate` call (cheap enough to run on every
/// `capabilities()` call, no memoization needed); webp encode is a static
/// platform fact — ImageIO can decode WebP but has no WebP encoder on
/// iOS/macOS, so it's always reported unsupported, never probed; heic is
/// detected via `CGImageDestinationCopyTypeIdentifiers`. Max hardware
/// resolution has no clean Apple API and is reported as `nil` rather than
/// a fabricated number.
enum CapabilityProbe {
  static func probe() -> CapabilitiesReportMessage {
    let hevcSupported = probeHevcEncoder()
    let heicSupported = probeHeicEncode()
    return CapabilitiesReportMessage(
      h264Encode: .supported,
      hevcEncode: hevcSupported ? .supported : .unsupported,
      aacEncode: .supported,
      webpEncode: .unsupported,
      heicEncode: heicSupported ? .supported : .unsupported,
      maxHardwareWidth: nil,
      maxHardwareHeight: nil
    )
  }

  /// Creates a tiny 64x64 HEVC compression session purely to check
  /// `noErr`, then invalidates it immediately.
  static func probeHevcEncoder() -> Bool {
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      width: 64,
      height: 64,
      codecType: kCMVideoCodecType_HEVC,
      encoderSpecification: nil,
      imageBufferAttributes: nil,
      compressedDataAllocator: nil,
      outputCallback: nil,
      refcon: nil,
      compressionSessionOut: &session
    )
    if let session = session {
      VTCompressionSessionInvalidate(session)
    }
    return status == noErr
  }

  static func probeHeicEncode() -> Bool {
    guard let types = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return false }
    return types.contains("public.heic")
  }
}

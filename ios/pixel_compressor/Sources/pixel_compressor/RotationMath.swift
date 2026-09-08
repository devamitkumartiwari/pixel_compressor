import CoreGraphics
import Foundation

/// Shared rotation helpers used by the image and thumbnail pipelines
/// (`ImageEngine`/`ThumbnailEngine`) and, for the EXIF-orientation<->degrees
/// table, by `MediaInfoEngine` when reporting an image's orientation.
///
/// Video rotation is handled separately in `VideoEngine`/
/// `VideoCodecSelection`: `AVAssetTrack.preferredTransform` is a full
/// affine transform (not a simple degrees value), so video composes
/// transforms directly rather than going through this degrees-based helper.
enum RotationMath {
  /// Combines a source-implied rotation with a caller-requested rotation
  /// into a single normalized `[0, 360)` degrees value.
  static func combine(sourceDegrees: Int, requestedDegrees: Int) -> Int {
    normalize(sourceDegrees + requestedDegrees)
  }

  /// Validates that a caller-supplied rotation is one of 0/90/180/270 —
  /// the only values the public Dart API documents and `assert()`s, an
  /// assert that's compiled out of release builds, so this is the actual
  /// enforcement. Both the image (canvas dimension swap in
  /// `ImageFormatCodec.rotate`) and video (`AVMutableVideoComposition`
  /// render-size swap in `VideoEngine`) pipelines only handle rotation in
  /// 90-degree steps and produce a clipped/wrong result for anything else.
  static func requireCardinal(_ degrees: Int) throws -> Int {
    guard degrees == 0 || degrees == 90 || degrees == 180 || degrees == 270 else {
      throw PixelCompressorError.invalidMedia(
        "rotationDegrees must be one of 0, 90, 180, 270, got \(degrees)")
    }
    return degrees
  }

  static func normalize(_ degrees: Int) -> Int {
    let mod = degrees % 360
    return mod < 0 ? mod + 360 : mod
  }

  /// Maps a `kCGImagePropertyOrientation` EXIF tag value (1-8) to the
  /// clockwise rotation already baked into the pixels by that tag. Mirrored
  /// variants (2, 4, 5, 7) are treated the same as their non-mirrored
  /// counterpart for rotation purposes — this pipeline bakes a plain
  /// rotation and doesn't attempt to reproduce a horizontal/vertical flip.
  static func degrees(forExifOrientation orientation: Int) -> Int {
    switch orientation {
    case 1, 2: return 0
    case 3, 4: return 180
    case 6, 5: return 90
    case 8, 7: return 270
    default: return 0
    }
  }

  /// Inverse of `degrees(forExifOrientation:)`, used when writing the
  /// EXIF orientation tag back out for `ExifPolicy.keep` after pixels have
  /// already been rotated upright (so the tag is always written as 1 for
  /// baked output — this exists mainly for documentation/testing symmetry).
  static func exifOrientation(forDegrees degrees: Int) -> Int {
    switch normalize(degrees) {
    case 90: return 6
    case 180: return 3
    case 270: return 8
    default: return 1
    }
  }
}

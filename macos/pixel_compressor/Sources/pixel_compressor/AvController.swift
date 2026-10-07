import AVFoundation

/// Async (iOS 16 / macOS 13) replacements for the synchronous AVAsset
/// property accessors deprecated in the iOS 16+ SDKs.
enum AvController {
    static func getVideoAsset(_ url: URL) -> AVURLAsset {
        return AVURLAsset(url: url)
    }

    static func getTrack(_ asset: AVAsset) async -> AVAssetTrack? {
        return try? await asset.loadTracks(withMediaType: .video).first
    }

    static func getVideoOrientation(_ track: AVAssetTrack) async -> Int? {
        guard let (size, txf) = try? await track.load(.naturalSize, .preferredTransform) else {
            return nil
        }
        if size.width == txf.tx && size.height == txf.ty {
            return 0
        } else if txf.tx == 0 && txf.ty == 0 {
            return 90
        } else if txf.tx == 0 && txf.ty == size.width {
            return 180
        } else {
            return 270
        }
    }

    static func getMetaDataByTag(_ asset: AVAsset, key: String) async -> String {
        guard let metadata = try? await asset.load(.commonMetadata) else { return "" }
        for item in metadata where item.commonKey?.rawValue == key {
            return (try? await item.load(.stringValue)) ?? ""
        }
        return ""
    }
}

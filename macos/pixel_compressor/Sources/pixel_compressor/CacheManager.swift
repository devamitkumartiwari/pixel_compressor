import Foundation

/// Manages the plugin-owned cache subtree
/// `<cachesDirectory>/pixel_compressor/{images,videos,thumbnails}`, created
/// lazily on first use. Used both to resolve output paths for requests that
/// don't specify `outputPath` and to back `CacheHostApi`.
final class CacheManager: @unchecked Sendable {
  enum Kind: String {
    case images
    case videos
    case thumbnails
  }

  private let fileManager = FileManager.default
  private let rootURL: URL

  init() {
    let cachesURL =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    rootURL = cachesURL.appendingPathComponent("pixel_compressor", isDirectory: true)
  }

  private func directory(for kind: Kind) throws -> URL {
    let dir = rootURL.appendingPathComponent(kind.rawValue, isDirectory: true)
    if !fileManager.fileExists(atPath: dir.path) {
      do {
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
      } catch {
        throw PixelCompressorError.encodingError(
          "Could not create cache directory: \(error.localizedDescription)")
      }
    }
    return dir
  }

  /// Resolves a fresh output path under the given cache subtree, using
  /// `fileName` (expected to already be unique, e.g. `<taskId>.jpg`).
  func resolveOutputPath(kind: Kind, fileName: String) throws -> String {
    let dir = try directory(for: kind)
    return dir.appendingPathComponent(fileName).path
  }

  /// Recursive byte sum of everything under the cache root; 0 if the root
  /// doesn't exist yet.
  func size() -> Int64 {
    guard fileManager.fileExists(atPath: rootURL.path) else { return 0 }
    var total: Int64 = 0
    if
      let enumerator = fileManager.enumerator(
        at: rootURL, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
    {
      for case let fileURL as URL in enumerator {
        if
          let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
          let size = values.fileSize
        {
          total += Int64(size)
        }
      }
    }
    return total
  }

  /// Deletes the entire cache subtree and recreates an empty root.
  func clear() throws {
    do {
      if fileManager.fileExists(atPath: rootURL.path) {
        try fileManager.removeItem(at: rootURL)
      }
      try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    } catch {
      throw PixelCompressorError.encodingError(
        "Could not clear cache: \(error.localizedDescription)")
    }
  }
}

import Foundation

enum VideoUtility {
    static let fileManager = FileManager.default

    /// Temp dir: excluded from backups and reclaimable by the system.
    static func basePath() -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("pixel_compressor/video")
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        }
        return path
    }

    static func stripFileExtension(_ fileName: String) -> String {
        var components = fileName.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            return components.joined(separator: ".")
        } else {
            return fileName
        }
    }

    static func getFileName(_ path: String) -> String {
        return stripFileExtension((path as NSString).lastPathComponent)
    }

    static func getPathUrl(_ path: String) -> URL {
        return URL(fileURLWithPath: excludeFileProtocol(path))
    }

    static func excludeFileProtocol(_ path: String) -> String {
        return path.replacingOccurrences(of: "file://", with: "")
    }

    static func excludeEncoding(_ path: String) -> String {
        return path.removingPercentEncoding ?? path
    }

    static func keyValueToJson(_ keyAndValue: [String: Any?]) -> String {
        let dictionary = keyAndValue.mapValues { $0 ?? NSNull() }
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func deleteFile(_ path: String, clear: Bool = false) {
        let url = getPathUrl(path)
        // Check `url.path`, not `url.absoluteString` ("file://…"), which
        // never exists on disk.
        if fileManager.fileExists(atPath: url.path) || clear {
            try? fileManager.removeItem(at: url)
        }
    }
}

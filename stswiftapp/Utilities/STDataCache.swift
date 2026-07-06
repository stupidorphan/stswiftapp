import Foundation
import OSLog

/// Simple file-based cache for API responses. Loads cached data instantly,
/// then allows background refresh so the UI never waits.
struct STDataCache {
    private static let log = Logger(subsystem: "com.stswiftapp", category: "Cache")
    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("STCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(for key: String) -> URL {
        cacheDir.appendingPathComponent(key + ".json")
    }

    static func read<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        let file = url(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            log.debug("Cache hit: \(key)")
            return value
        } catch {
            log.warning("Cache decode failed for \(key): \(error.localizedDescription)")
            return nil
        }
    }

    static func write<T: Encodable>(_ key: String, value: T) {
        let file = url(for: key)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: file, options: .atomic)
            log.debug("Cache write: \(key)")
        } catch {
            log.warning("Cache write failed for \(key): \(error.localizedDescription)")
        }
    }

    static func readRaw(_ key: String) -> Data? {
        try? Data(contentsOf: url(for: key))
    }

    static func writeRaw(_ key: String, data: Data) {
        try? data.write(to: url(for: key), options: .atomic)
    }
}

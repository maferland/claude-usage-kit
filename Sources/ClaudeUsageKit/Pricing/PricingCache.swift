import Foundation

/// Disk cache for LiteLLM pricing data.
enum PricingCache {
    static let cacheTTL: TimeInterval = 24 * 60 * 60 // 1 day

    static let cacheFile: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("com.maferland.claudeusagekit/litellm-pricing.json")
    }()

    static func save(_ data: Data) {
        let dir = cacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: cacheFile)
    }
}

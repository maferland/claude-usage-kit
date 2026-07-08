import Foundation

/// Reads Claude Code JSONL session files and aggregates into daily usage data.
/// Scans ~/.claude/projects/**/*.jsonl, extracts assistant message usage data,
/// and aggregates into CCUsageResponse.
public enum SessionReader {

    struct DayModelKey: Hashable {
        let date: String
        let model: String
    }

    /// One usage-bearing assistant line, cached so unchanged files aren't re-parsed.
    struct ParsedLine: Codable {
        let id: String?
        let date: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
    }

    struct CacheEntry: Codable {
        let mtime: Date
        let lines: [ParsedLine]
    }

    // Bump when the on-disk shape changes; a mismatch makes the whole file ignored.
    private static let cacheFormatVersion = 1

    private struct PersistedCache: Codable {
        let version: Int
        let entries: [String: CacheEntry]
    }

    // Keyed by file path + mtime, mirrored to disk so a fresh process reuses it
    // instead of re-parsing all history. Lock-guarded for Burn's overlapping refreshes.
    private static var parseCache: [String: CacheEntry] = [:]
    private static var cacheLoaded = false
    private static var cacheDirty = false
    private static let cacheLock = NSLock()
    private static let persistQueue = DispatchQueue(label: "ClaudeUsageKit.parseCache.persist")

    static var cacheFileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("ClaudeUsageKit/parse-cache.json")
    }()

    static func resetCacheForTesting(fileURL: URL) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        parseCache = [:]
        cacheLoaded = false
        cacheDirty = false
        cacheFileURL = fileURL
    }

    static func flushPersistForTesting() {
        persistQueue.sync {}
    }

    // Caller must hold cacheLock.
    private static func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode(PersistedCache.self, from: data),
              decoded.version == cacheFormatVersion else { return }
        parseCache = decoded.entries
    }

    static func parsedLines(for url: URL) -> [ParsedLine] {
        let path = url.path
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date

        cacheLock.lock()
        loadCacheIfNeeded()
        if let mtime, let cached = parseCache[path], cached.mtime == mtime {
            cacheLock.unlock()
            return cached.lines
        }
        cacheLock.unlock()

        var lines: [ParsedLine] = []
        autoreleasepool {
            JSONLReader.parseFile(url) { _, msg, usage, model, dateStr in
                lines.append(ParsedLine(
                    id: msg.id, date: dateStr, model: model,
                    inputTokens: usage.input_tokens ?? 0,
                    outputTokens: usage.output_tokens ?? 0,
                    cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
                    cacheReadTokens: usage.cache_read_input_tokens ?? 0
                ))
            }
        }

        if let mtime {
            cacheLock.lock()
            parseCache[path] = CacheEntry(mtime: mtime, lines: lines)
            cacheDirty = true
            cacheLock.unlock()
        }
        return lines
    }

    /// Drop entries for files no longer present, then write the cache to disk on a
    /// background queue if anything changed (off the hot path).
    private static func persistCache(currentPaths: Set<String>) {
        cacheLock.lock()
        let pruned = parseCache.filter { currentPaths.contains($0.key) }
        if pruned.count != parseCache.count {
            parseCache = pruned
            cacheDirty = true
        }
        guard cacheDirty else { cacheLock.unlock(); return }
        cacheDirty = false
        let snapshot = PersistedCache(version: cacheFormatVersion, entries: parseCache)
        cacheLock.unlock()

        persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: cacheFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    public static func readUsage() throws -> CCUsageResponse {
        let claudeDir = JSONLReader.projectsDirectory

        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            return CCUsageResponse(daily: [], totals: Totals(
                inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                cacheReadTokens: 0, totalTokens: 0, totalCost: 0
            ))
        }

        let files = JSONLReader.findJSONLFiles(in: claudeDir)
        return readUsage(from: files, pricing: PricingService.fetchPricing())
    }

    // Resumed/forked Claude Code sessions replay prior turns into new JSONL files, so the same assistant message appears in multiple files. Dedup by message.id to match ccusage's count.
    static func readUsage(from files: [URL], pricing: [String: ModelPricing]) -> CCUsageResponse {
        var buckets: [DayModelKey: TokenBucket] = [:]
        var seenIds = Set<String>()

        for fileURL in files {
            for line in parsedLines(for: fileURL) {
                if let id = line.id, !seenIds.insert(id).inserted { continue }
                let key = DayModelKey(date: line.date, model: line.model)
                buckets[key, default: TokenBucket()].add(
                    input: line.inputTokens, output: line.outputTokens,
                    cacheCreation: line.cacheCreationTokens, cacheRead: line.cacheReadTokens)
            }
        }

        persistCache(currentPaths: Set(files.map(\.path)))
        return buildResponse(from: buckets, pricing: pricing)
    }

    static func buildResponse(
        from buckets: [DayModelKey: TokenBucket],
        pricing pricingTable: [String: ModelPricing]
    ) -> CCUsageResponse {
        var byDate: [String: [(model: String, bucket: TokenBucket)]] = [:]
        for (key, bucket) in buckets {
            byDate[key.date, default: []].append((key.model, bucket))
        }

        var totalBucket = TokenBucket()
        var totalCost = 0.0

        let daily: [DailyUsage] = byDate.keys.sorted().map { date in
            let entries = byDate[date]!
            var dayBucket = TokenBucket()
            var dayCost = 0.0
            var models: [String] = []
            var breakdowns: [ModelBreakdown] = []

            for (model, bucket) in entries.sorted(by: { $0.model < $1.model }) {
                let p = PricingService.resolvePricing(for: model, from: pricingTable)
                let cost = bucket.cost(pricing: p)
                dayBucket.inputTokens += bucket.inputTokens
                dayBucket.outputTokens += bucket.outputTokens
                dayBucket.cacheCreationTokens += bucket.cacheCreationTokens
                dayBucket.cacheReadTokens += bucket.cacheReadTokens
                dayCost += cost
                models.append(model)
                breakdowns.append(ModelBreakdown(
                    modelName: model,
                    inputTokens: bucket.inputTokens,
                    outputTokens: bucket.outputTokens,
                    cacheCreationTokens: bucket.cacheCreationTokens,
                    cacheReadTokens: bucket.cacheReadTokens,
                    cost: cost
                ))
            }

            totalBucket.inputTokens += dayBucket.inputTokens
            totalBucket.outputTokens += dayBucket.outputTokens
            totalBucket.cacheCreationTokens += dayBucket.cacheCreationTokens
            totalBucket.cacheReadTokens += dayBucket.cacheReadTokens
            totalCost += dayCost

            return DailyUsage(
                date: date,
                inputTokens: dayBucket.inputTokens,
                outputTokens: dayBucket.outputTokens,
                cacheCreationTokens: dayBucket.cacheCreationTokens,
                cacheReadTokens: dayBucket.cacheReadTokens,
                totalTokens: dayBucket.totalTokens,
                totalCost: dayCost,
                modelsUsed: models,
                modelBreakdowns: breakdowns
            )
        }

        let totals = Totals(
            inputTokens: totalBucket.inputTokens,
            outputTokens: totalBucket.outputTokens,
            cacheCreationTokens: totalBucket.cacheCreationTokens,
            cacheReadTokens: totalBucket.cacheReadTokens,
            totalTokens: totalBucket.totalTokens,
            totalCost: totalCost
        )

        return CCUsageResponse(daily: daily, totals: totals)
    }
}

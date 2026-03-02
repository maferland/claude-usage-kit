import Foundation

/// Reads per-session usage data from Claude Code JSONL files.
public enum SessionFileReader {

    /// Read sessions from ~/.claude/projects, returning per-session cost/token/model data.
    /// - Parameter since: Only include files modified after this date. Defaults to 30 days ago.
    public static func readAllSessions(since: Date? = nil) throws -> [SessionUsage] {
        let claudeDir = JSONLReader.projectsDirectory
        let fm = FileManager.default

        guard fm.fileExists(atPath: claudeDir.path) else { return [] }

        let cutoff = since ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let pricingTable = PricingService.fetchPricing()

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: claudeDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var sessions: [SessionUsage] = []

        for projectDir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let projectPath = decodePath(projectDir.lastPathComponent)

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Skip files not modified since cutoff
                if let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   modDate < cutoff { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                if let usage = readSession(
                    sessionId: sessionId,
                    projectPath: projectPath,
                    file: file,
                    pricingTable: pricingTable
                ) {
                    sessions.append(usage)
                }
            }
        }

        return sessions.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
    }

    private static func readSession(
        sessionId: String,
        projectPath: String,
        file: URL,
        pricingTable: [String: ModelPricing]
    ) -> SessionUsage? {
        var modelBuckets: [String: TokenBucket] = [:]
        var modelsOrdered: [String] = []
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var messageCount = 0

        JSONLReader.parseFile(file) { entry, _, usage, model, _ in
            if modelBuckets[model] == nil {
                modelsOrdered.append(model)
            }
            modelBuckets[model, default: TokenBucket()].add(usage)
            messageCount += 1

            if let ts = entry.timestamp, let date = JSONLReader.parseDate(from: ts) {
                if firstTimestamp == nil || date < firstTimestamp! { firstTimestamp = date }
                if lastTimestamp == nil || date > lastTimestamp! { lastTimestamp = date }
            }
        }

        guard !modelBuckets.isEmpty else { return nil }

        var totalBucket = TokenBucket()
        var totalCost = 0.0
        var breakdowns: [ModelBreakdown] = []

        var maxTokens = 0
        var primaryModel: String?

        for model in modelsOrdered {
            guard let bucket = modelBuckets[model] else { continue }
            let p = PricingService.resolvePricing(for: model, from: pricingTable)
            let cost = bucket.cost(pricing: p)

            totalBucket.inputTokens += bucket.inputTokens
            totalBucket.outputTokens += bucket.outputTokens
            totalBucket.cacheCreationTokens += bucket.cacheCreationTokens
            totalBucket.cacheReadTokens += bucket.cacheReadTokens
            totalCost += cost

            if bucket.totalTokens > maxTokens {
                maxTokens = bucket.totalTokens
                primaryModel = model
            }

            breakdowns.append(ModelBreakdown(
                modelName: model,
                inputTokens: bucket.inputTokens,
                outputTokens: bucket.outputTokens,
                cacheCreationTokens: bucket.cacheCreationTokens,
                cacheReadTokens: bucket.cacheReadTokens,
                cost: cost
            ))
        }

        return SessionUsage(
            sessionId: sessionId,
            projectPath: projectPath,
            startedAt: firstTimestamp,
            lastActivityAt: lastTimestamp,
            totalCost: totalCost,
            inputTokens: totalBucket.inputTokens,
            outputTokens: totalBucket.outputTokens,
            cacheCreationTokens: totalBucket.cacheCreationTokens,
            cacheReadTokens: totalBucket.cacheReadTokens,
            totalTokens: totalBucket.totalTokens,
            modelsUsed: modelsOrdered,
            primaryModel: primaryModel,
            modelBreakdowns: breakdowns,
            messageCount: messageCount
        )
    }

    // MARK: - Per-file cost

    private static var costCache: [String: (mtime: Date, info: FileCostInfo)] = [:]

    /// Read token usage and estimated cost from a single JSONL session file.
    /// Results are cached by file mtime.
    public static func readCostInfo(at url: URL) -> FileCostInfo? {
        let path = url.path
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let mtime, let cached = costCache[path], cached.mtime == mtime {
            return cached.info
        }

        let pricingTable = PricingService.fetchPricing()
        var modelBuckets: [String: TokenBucket] = [:]
        var maxTokens = 0
        var primaryModel: String?

        JSONLReader.parseFile(url) { _, _, usage, model, _ in
            modelBuckets[model, default: TokenBucket()].add(usage)
        }

        guard !modelBuckets.isEmpty else { return nil }

        var totalTokens = 0
        var totalCost = 0.0

        for (model, bucket) in modelBuckets {
            let pricing = PricingService.resolvePricing(for: model, from: pricingTable)
            totalTokens += bucket.totalTokens
            totalCost += bucket.cost(pricing: pricing)

            if bucket.totalTokens > maxTokens {
                maxTokens = bucket.totalTokens
                primaryModel = model
            }
        }

        let info = FileCostInfo(totalTokens: totalTokens, estimatedCost: totalCost, primaryModel: primaryModel)
        if let mtime {
            costCache[path] = (mtime, info)
        }
        return info
    }

    /// Decode Claude's encoded project directory name back to a filesystem path.
    /// Claude encodes by replacing both "/" and "." with "-", making "--" for "/." (dot-prefixed dirs).
    /// We walk the filesystem to resolve ambiguous dashes.
    private static func decodePath(_ encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }
        let stripped = String(encoded.dropFirst())
        return resolveEncodedPath(stripped, at: "/") ?? naiveDecode(stripped)
    }

    private static func naiveDecode(_ stripped: String) -> String {
        "/" + stripped.replacingOccurrences(of: "--", with: "/.").replacingOccurrences(of: "-", with: "/")
    }

    /// Normalize a name the same way Claude encodes: replace both "." and "/" with "-".
    private static func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
    }

    /// Cache for directory contents to avoid repeated listings.
    private static var dirCache: [String: [String]] = [:]

    private static func cachedContents(atPath path: String) -> [String]? {
        if let cached = dirCache[path] { return cached }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        dirCache[path] = contents
        return contents
    }

    /// Recursively resolve an encoded path against the actual filesystem.
    /// At each level, lists directory contents and finds entries whose normalized form
    /// matches the candidate (handling dots, dashes, and path separators).
    private static func resolveEncodedPath(_ encoded: String, at base: String) -> String? {
        guard !encoded.isEmpty else { return base }

        let dotPrefixed = encoded.hasPrefix("-")
        let work = dotPrefixed ? String(encoded.dropFirst()) : encoded
        let parts = work.components(separatedBy: "-")

        guard let contents = cachedContents(atPath: base) else { return nil }

        for i in 1...parts.count {
            if parts[0..<i].contains("") { break }

            var candidate = parts[0..<i].joined(separator: "-")
            if dotPrefixed { candidate = "." + candidate }
            let normalizedCandidate = normalize(candidate)

            for entry in contents {
                guard normalize(entry) == normalizedCandidate else { continue }

                let path = base == "/" ? "/\(entry)" : "\(base)/\(entry)"
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }

                let rest = parts[i...].joined(separator: "-")
                if rest.isEmpty { return path }
                if let result = resolveEncodedPath(rest, at: path) { return result }
            }
        }
        return nil
    }
}

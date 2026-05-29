import Foundation

/// Reads Claude Code JSONL session files and aggregates into daily usage data.
/// Scans ~/.claude/projects/**/*.jsonl, extracts assistant message usage data,
/// and aggregates into CCUsageResponse.
public enum SessionReader {

    struct DayModelKey: Hashable {
        let date: String
        let model: String
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
            autoreleasepool {
                JSONLReader.parseFile(fileURL) { _, msg, usage, model, dateStr in
                    if let id = msg.id, !seenIds.insert(id).inserted { return }
                    let key = DayModelKey(date: dateStr, model: model)
                    buckets[key, default: TokenBucket()].add(usage)
                }
            }
        }

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

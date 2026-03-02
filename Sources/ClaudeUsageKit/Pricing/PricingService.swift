import Foundation

/// Fetches and resolves Claude model pricing from LiteLLM with local caching.
public enum PricingService {

    private static let litellmURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    /// LiteLLM JSON entry shape
    private struct LiteLLMEntry: Decodable {
        let input_cost_per_token: Double?
        let output_cost_per_token: Double?
        let cache_creation_input_token_cost: Double?
        let cache_read_input_token_cost: Double?
    }

    /// Fetch pricing from LiteLLM (with local cache). Returns model name -> pricing map.
    public static func fetchPricing() -> [String: ModelPricing] {
        if let cached = loadCachedPricing() { return cached }
        if let fetched = fetchFromNetwork() { return fetched }
        return fallbackPricing
    }

    /// Resolve pricing for a model name with fuzzy family matching.
    public static func resolvePricing(for model: String, from table: [String: ModelPricing]) -> ModelPricing {
        if let p = table[model] { return p }

        let lower = model.lowercased()
        let family: String
        if lower.contains("opus") { family = "opus" }
        else if lower.contains("sonnet") { family = "sonnet" }
        else if lower.contains("haiku") { family = "haiku" }
        else { family = "opus" } // safe overestimate

        let candidates = table.filter { $0.key.lowercased().contains(family) }
        if let best = candidates.max(by: { $0.key < $1.key }) {
            return best.value
        }

        return fallbackPricing.values.first!
    }

    // MARK: - Cache

    private static func loadCachedPricing() -> [String: ModelPricing]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: PricingCache.cacheFile.path),
              let attrs = try? fm.attributesOfItem(atPath: PricingCache.cacheFile.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < PricingCache.cacheTTL,
              let data = try? Data(contentsOf: PricingCache.cacheFile) else {
            return nil
        }
        return parseLiteLLM(data)
    }

    private static func fetchFromNetwork() -> [String: ModelPricing]? {
        var request = URLRequest(url: litellmURL)
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: ModelPricing]?

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            PricingCache.save(data)
            result = parseLiteLLM(data)
        }
        task.resume()
        semaphore.wait()
        return result
    }

    private static func parseLiteLLM(_ data: Data) -> [String: ModelPricing]? {
        guard let raw = try? JSONDecoder().decode([String: LiteLLMEntry].self, from: data) else {
            return nil
        }

        var pricing: [String: ModelPricing] = [:]
        for (key, entry) in raw {
            let lower = key.lowercased()
            guard lower.hasPrefix("claude-") || lower.hasPrefix("anthropic/claude-") || lower.hasPrefix("anthropic.claude-") else {
                continue
            }
            guard let input = entry.input_cost_per_token,
                  let output = entry.output_cost_per_token else { continue }

            let modelName: String
            if lower.hasPrefix("anthropic/") {
                modelName = String(key.dropFirst("anthropic/".count))
            } else if lower.hasPrefix("anthropic.") {
                modelName = String(key.dropFirst("anthropic.".count))
            } else {
                modelName = key
            }

            pricing[modelName] = ModelPricing(
                inputCostPerToken: input,
                outputCostPerToken: output,
                cacheCreationCostPerToken: entry.cache_creation_input_token_cost ?? input,
                cacheReadCostPerToken: entry.cache_read_input_token_cost ?? input
            )
        }
        return pricing.isEmpty ? nil : pricing
    }

    /// Hardcoded fallback (Opus 4.6, Sonnet 4.6, Haiku 4.5 rates)
    static let fallbackPricing: [String: ModelPricing] = {
        var p: [String: ModelPricing] = [:]
        let opus = ModelPricing(inputCostPerToken: 5e-06, outputCostPerToken: 2.5e-05,
                                cacheCreationCostPerToken: 6.25e-06, cacheReadCostPerToken: 5e-07)
        let sonnet = ModelPricing(inputCostPerToken: 3e-06, outputCostPerToken: 1.5e-05,
                                  cacheCreationCostPerToken: 3.75e-06, cacheReadCostPerToken: 3e-07)
        let haiku = ModelPricing(inputCostPerToken: 1e-06, outputCostPerToken: 5e-06,
                                 cacheCreationCostPerToken: 1.25e-06, cacheReadCostPerToken: 1e-07)
        p["claude-opus-4-6"] = opus
        p["claude-sonnet-4-6"] = sonnet
        p["claude-haiku-4-5"] = haiku
        return p
    }()
}

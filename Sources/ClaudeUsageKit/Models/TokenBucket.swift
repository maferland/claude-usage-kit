import Foundation

struct TokenBucket {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    mutating func add(_ usage: JSONLReader.Usage) {
        inputTokens += usage.input_tokens ?? 0
        outputTokens += usage.output_tokens ?? 0
        cacheCreationTokens += usage.cache_creation_input_tokens ?? 0
        cacheReadTokens += usage.cache_read_input_tokens ?? 0
    }

    func cost(pricing: ModelPricing) -> Double {
        Double(inputTokens) * pricing.inputCostPerToken
            + Double(outputTokens) * pricing.outputCostPerToken
            + Double(cacheCreationTokens) * pricing.cacheCreationCostPerToken
            + Double(cacheReadTokens) * pricing.cacheReadCostPerToken
    }
}

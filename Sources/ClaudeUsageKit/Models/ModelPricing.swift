import Foundation

public struct ModelPricing: Sendable {
    public let inputCostPerToken: Double
    public let outputCostPerToken: Double
    public let cacheCreationCostPerToken: Double
    public let cacheReadCostPerToken: Double

    public init(
        inputCostPerToken: Double,
        outputCostPerToken: Double,
        cacheCreationCostPerToken: Double,
        cacheReadCostPerToken: Double
    ) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheCreationCostPerToken = cacheCreationCostPerToken
        self.cacheReadCostPerToken = cacheReadCostPerToken
    }
}

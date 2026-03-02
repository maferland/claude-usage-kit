import Foundation

/// Lightweight per-file cost summary for consumers that need single-session cost lookups.
public struct FileCostInfo: Sendable {
    public let totalTokens: Int
    public let estimatedCost: Double
    public let primaryModel: String?

    public init(totalTokens: Int, estimatedCost: Double, primaryModel: String?) {
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
        self.primaryModel = primaryModel
    }
}

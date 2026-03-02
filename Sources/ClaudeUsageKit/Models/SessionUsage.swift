import Foundation

public struct SessionUsage: Identifiable, Codable, Sendable {
    public let sessionId: String
    public let projectPath: String
    public let startedAt: Date?
    public let lastActivityAt: Date?
    public let totalCost: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let totalTokens: Int
    public let modelsUsed: [String]
    public let primaryModel: String?
    public let modelBreakdowns: [ModelBreakdown]
    public let messageCount: Int

    public var id: String { sessionId }

    public init(
        sessionId: String, projectPath: String,
        startedAt: Date?, lastActivityAt: Date?,
        totalCost: Double, inputTokens: Int, outputTokens: Int,
        cacheCreationTokens: Int, cacheReadTokens: Int, totalTokens: Int,
        modelsUsed: [String], primaryModel: String?,
        modelBreakdowns: [ModelBreakdown], messageCount: Int
    ) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.totalCost = totalCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.modelsUsed = modelsUsed
        self.primaryModel = primaryModel
        self.modelBreakdowns = modelBreakdowns
        self.messageCount = messageCount
    }
}

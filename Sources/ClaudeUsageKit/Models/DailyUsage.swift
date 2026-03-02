import Foundation

public struct CCUsageResponse: Codable, Sendable {
    public let daily: [DailyUsage]
    public let totals: Totals

    public init(daily: [DailyUsage], totals: Totals) {
        self.daily = daily
        self.totals = totals
    }
}

public struct DailyUsage: Codable, Identifiable, Sendable {
    public var id: String { date }

    public let date: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let totalTokens: Int
    public let totalCost: Double
    public let modelsUsed: [String]
    public let modelBreakdowns: [ModelBreakdown]

    public init(
        date: String, inputTokens: Int, outputTokens: Int,
        cacheCreationTokens: Int, cacheReadTokens: Int,
        totalTokens: Int, totalCost: Double,
        modelsUsed: [String], modelBreakdowns: [ModelBreakdown]
    ) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.modelsUsed = modelsUsed
        self.modelBreakdowns = modelBreakdowns
    }
}

public struct ModelBreakdown: Codable, Sendable {
    public let modelName: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let cost: Double

    public init(
        modelName: String, inputTokens: Int, outputTokens: Int,
        cacheCreationTokens: Int, cacheReadTokens: Int, cost: Double
    ) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.cost = cost
    }
}

public struct Totals: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let totalTokens: Int
    public let totalCost: Double

    public init(
        inputTokens: Int, outputTokens: Int,
        cacheCreationTokens: Int, cacheReadTokens: Int,
        totalTokens: Int, totalCost: Double
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.totalCost = totalCost
    }
}

public struct UsageData: Sendable {
    public let todayCost: Double
    public let last7Days: [DailyUsage]
    public let monthTotal: Double
    public let isCurrentWeek: Bool
    public let weekStart: Date
    public let weekEnd: Date
    public let lastRefreshDate: Date
    public let earliestDate: String?

    public var weekTotal: Double { last7Days.reduce(0) { $0 + $1.totalCost } }

    public var canGoBack: Bool {
        guard let earliest = earliestDate else { return false }
        let startStr = Self.dateString(from: weekStart)
        return startStr > earliest
    }

    public static let empty = UsageData(
        todayCost: 0, last7Days: [], monthTotal: 0,
        isCurrentWeek: true, weekStart: Date(), weekEnd: Date(),
        lastRefreshDate: .distantPast, earliestDate: nil
    )

    public init(
        todayCost: Double, last7Days: [DailyUsage], monthTotal: Double,
        isCurrentWeek: Bool, weekStart: Date, weekEnd: Date,
        lastRefreshDate: Date, earliestDate: String?
    ) {
        self.todayCost = todayCost
        self.last7Days = last7Days
        self.monthTotal = monthTotal
        self.isCurrentWeek = isCurrentWeek
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.lastRefreshDate = lastRefreshDate
        self.earliestDate = earliestDate
    }

    public static func from(response: CCUsageResponse, weekOffset: Int = 0) -> UsageData {
        let calendar = Calendar.current
        let now = Date()
        let today = dateString(from: now)
        let todayCost = response.daily.first { $0.date == today }?.totalCost ?? 0

        let endDay = calendar.date(byAdding: .day, value: weekOffset * 7, to: now)!
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay)!

        let existingByDate = Dictionary(
            uniqueKeysWithValues: response.daily.map { ($0.date, $0) }
        )
        let last7Days: [DailyUsage] = (0...6).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: startDay)!
            let dayStr = dateString(from: day)
            return existingByDate[dayStr] ?? DailyUsage(
                date: dayStr, inputTokens: 0, outputTokens: 0,
                cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 0,
                totalCost: 0, modelsUsed: [], modelBreakdowns: []
            )
        }

        let monthPrefix = String(dateString(from: endDay).prefix(7))
        let monthTotal = response.daily
            .filter { $0.date.hasPrefix(monthPrefix) }
            .reduce(0) { $0 + $1.totalCost }

        let earliestDate = response.daily.filter { $0.totalCost > 0 }.min(by: { $0.date < $1.date })?.date

        return UsageData(
            todayCost: todayCost, last7Days: last7Days, monthTotal: monthTotal,
            isCurrentWeek: weekOffset == 0, weekStart: startDay, weekEnd: endDay,
            lastRefreshDate: now, earliestDate: earliestDate
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    public static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

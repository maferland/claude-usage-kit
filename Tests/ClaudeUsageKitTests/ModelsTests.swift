import XCTest
@testable import ClaudeUsageKit

final class ModelsTests: XCTestCase {

    // MARK: - JSON Parsing

    func testDecodeCCUsageResponse() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)

        XCTAssertEqual(response.daily.count, 3)
        XCTAssertEqual(response.daily[0].date, sampleDates[0])
        XCTAssertEqual(response.daily[0].totalCost, 12.50)
        XCTAssertEqual(response.daily[0].inputTokens, 100_000)
        XCTAssertEqual(response.daily[0].outputTokens, 50_000)
        XCTAssertEqual(response.daily[0].modelsUsed, ["claude-opus-4-6"])
        XCTAssertEqual(response.daily[0].modelBreakdowns.count, 1)
        XCTAssertEqual(response.daily[0].modelBreakdowns[0].modelName, "claude-opus-4-6")
        XCTAssertEqual(response.daily[0].modelBreakdowns[0].cost, 12.50)
        XCTAssertEqual(response.totals.totalCost, 118.82)
    }

    func testDecodeEmptyDaily() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(response.daily.isEmpty)
        XCTAssertEqual(response.totals.totalCost, 0)
    }

    // MARK: - Aggregation

    func testUsageDataFromResponse() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)
        let usage = UsageData.from(response: response)

        XCTAssertEqual(usage.todayCost, 68.82)
        XCTAssertFalse(usage.last7Days.isEmpty)
        XCTAssertTrue(usage.monthTotal > 0)
        XCTAssertNotEqual(usage.lastRefreshDate, .distantPast)
    }

    func testUsageDataNoToday() throws {
        let json = """
        {"daily":[{"date":"2025-01-01","inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":5.00,"modelsUsed":["opus"],"modelBreakdowns":[]}],"totals":{"inputTokens":100,"outputTokens":50,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":150,"totalCost":5.00}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.todayCost, 0)
    }

    func testUsageDataEmpty() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.todayCost, 0)
        XCTAssertEqual(usage.last7Days.count, 7)
        XCTAssertTrue(usage.last7Days.allSatisfy { $0.totalCost == 0 })
        XCTAssertEqual(usage.monthTotal, 0)
    }

    func testLast7DaysSorted() throws {
        let data = sampleJSON.data(using: .utf8)!
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: data)
        let usage = UsageData.from(response: response)

        let dates = usage.last7Days.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    // MARK: - Week Navigation

    func testWeekOffsetZeroIsCurrentWeek() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: 0)
        XCTAssertTrue(usage.isCurrentWeek)
    }

    func testWeekOffsetNegativeIsNotCurrentWeek() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: -1)
        XCTAssertFalse(usage.isCurrentWeek)
    }

    func testWeekOffsetShiftsDays() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let current = UsageData.from(response: response, weekOffset: 0)
        let previous = UsageData.from(response: response, weekOffset: -1)

        XCTAssertEqual(current.last7Days.count, 7)
        XCTAssertEqual(previous.last7Days.count, 7)
        XCTAssertLessThan(previous.last7Days.last!.date, current.last7Days.first!.date)
    }

    func testWeekTotalComputedProperty() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response, weekOffset: 0)
        let expected = usage.last7Days.reduce(0) { $0 + $1.totalCost }
        XCTAssertEqual(usage.weekTotal, expected, accuracy: 0.001)
    }

    func testTodayCostUnchangedByOffset() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let current = UsageData.from(response: response, weekOffset: 0)
        let past = UsageData.from(response: response, weekOffset: -2)
        XCTAssertEqual(current.todayCost, past.todayCost)
    }

    // MARK: - Earliest Date & canGoBack

    func testEarliestDatePopulated() throws {
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: sampleJSON.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertEqual(usage.earliestDate, sampleDates[0])
    }

    func testEarliestDateNilForEmptyResponse() throws {
        let json = """
        {"daily":[],"totals":{"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"totalTokens":0,"totalCost":0}}
        """
        let response = try JSONDecoder().decode(CCUsageResponse.self, from: json.data(using: .utf8)!)
        let usage = UsageData.from(response: response)
        XCTAssertNil(usage.earliestDate)
    }

    func testCanGoBackFalseWhenNoData() {
        XCTAssertFalse(UsageData.empty.canGoBack)
    }

    // MARK: - Sample Data

    private var sampleDates: [String] {
        let today = Date()
        return (0..<3).map { i in
            UsageData.dateString(from: Calendar.current.date(byAdding: .day, value: -(2 - i), to: today)!)
        }
    }

    private var sampleJSON: String {
        let d = sampleDates
        return """
        {
            "daily": [
                {"date":"\(d[0])","inputTokens":100000,"outputTokens":50000,"cacheCreationTokens":10000,"cacheReadTokens":5000,"totalTokens":165000,"totalCost":12.50,"modelsUsed":["claude-opus-4-6"],"modelBreakdowns":[{"modelName":"claude-opus-4-6","inputTokens":100000,"outputTokens":50000,"cacheCreationTokens":10000,"cacheReadTokens":5000,"cost":12.50}]},
                {"date":"\(d[1])","inputTokens":200000,"outputTokens":80000,"cacheCreationTokens":20000,"cacheReadTokens":8000,"totalTokens":308000,"totalCost":37.50,"modelsUsed":["claude-opus-4-6","claude-sonnet-4-20250514"],"modelBreakdowns":[{"modelName":"claude-opus-4-6","inputTokens":150000,"outputTokens":60000,"cacheCreationTokens":15000,"cacheReadTokens":6000,"cost":30.00},{"modelName":"claude-sonnet-4-20250514","inputTokens":50000,"outputTokens":20000,"cacheCreationTokens":5000,"cacheReadTokens":2000,"cost":7.50}]},
                {"date":"\(d[2])","inputTokens":500000,"outputTokens":200000,"cacheCreationTokens":50000,"cacheReadTokens":20000,"totalTokens":770000,"totalCost":68.82,"modelsUsed":["claude-opus-4-6"],"modelBreakdowns":[{"modelName":"claude-opus-4-6","inputTokens":500000,"outputTokens":200000,"cacheCreationTokens":50000,"cacheReadTokens":20000,"cost":68.82}]}
            ],
            "totals": {"inputTokens":800000,"outputTokens":330000,"cacheCreationTokens":80000,"cacheReadTokens":33000,"totalTokens":1243000,"totalCost":118.82}
        }
        """
    }
}

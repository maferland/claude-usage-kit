import XCTest
@testable import ClaudeUsageKit

final class SessionReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeUsageKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDedupesMessagesAcrossFilesById() throws {
        let timestamp = "2026-05-28T12:00:00.000Z"
        let lineA = makeAssistantLine(id: "msg_dup", model: "claude-opus-4-7", input: 1000, output: 500, timestamp: timestamp)
        let lineB = makeAssistantLine(id: "msg_unique", model: "claude-opus-4-7", input: 200, output: 100, timestamp: timestamp)

        try (lineA + "\n" + lineB).write(to: tempDir.appendingPathComponent("session1.jsonl"), atomically: true, encoding: .utf8)
        // session2 replays the same msg_dup (resumed session) plus a unique one
        let lineC = makeAssistantLine(id: "msg_other", model: "claude-opus-4-7", input: 50, output: 25, timestamp: timestamp)
        try (lineA + "\n" + lineC).write(to: tempDir.appendingPathComponent("session2.jsonl"), atomically: true, encoding: .utf8)

        let files = JSONLReader.findJSONLFiles(in: tempDir)
        let response = SessionReader.readUsage(from: files, pricing: stubPricing)

        XCTAssertEqual(response.totals.inputTokens, 1000 + 200 + 50)
        XCTAssertEqual(response.totals.outputTokens, 500 + 100 + 25)
    }

    func testCountsMessagesWithoutIdEveryTime() throws {
        let timestamp = "2026-05-28T12:00:00.000Z"
        let noIdLine = makeAssistantLine(id: nil, model: "claude-opus-4-7", input: 100, output: 50, timestamp: timestamp)
        try (noIdLine + "\n" + noIdLine).write(to: tempDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let files = JSONLReader.findJSONLFiles(in: tempDir)
        let response = SessionReader.readUsage(from: files, pricing: stubPricing)

        XCTAssertEqual(response.totals.inputTokens, 200)
        XCTAssertEqual(response.totals.outputTokens, 100)
    }

    private func makeAssistantLine(id: String?, model: String, input: Int, output: Int, timestamp: String) -> String {
        let idField = id.map { "\"id\":\"\($0)\"," } ?? ""
        return """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"role":"assistant",\(idField)"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    private var stubPricing: [String: ModelPricing] {
        ["claude-opus-4-7": ModelPricing(
            inputCostPerToken: 5e-06, outputCostPerToken: 2.5e-05,
            cacheCreationCostPerToken: 6.25e-06, cacheReadCostPerToken: 5e-07
        )]
    }
}

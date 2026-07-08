import XCTest
@testable import ClaudeUsageKit

final class SessionReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudeUsageKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Isolate the shared parse cache from the real one and from other tests.
        SessionReader.resetCacheForTesting(fileURL: tempDir.appendingPathComponent("parse-cache.json"))
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

    func testReReadsFileAfterModification() throws {
        let timestamp = "2026-05-28T12:00:00.000Z"
        let file = tempDir.appendingPathComponent("session.jsonl")

        try makeAssistantLine(id: "m1", model: "claude-opus-4-7", input: 100, output: 50, timestamp: timestamp)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: file.path)
        let first = SessionReader.readUsage(from: [file], pricing: stubPricing)
        XCTAssertEqual(first.totals.inputTokens, 100)

        try makeAssistantLine(id: "m2", model: "claude-opus-4-7", input: 777, output: 50, timestamp: timestamp)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: file.path)
        let second = SessionReader.readUsage(from: [file], pricing: stubPricing)
        XCTAssertEqual(second.totals.inputTokens, 777, "new mtime should invalidate the parse cache")
    }

    func testPersistsCacheToDisk() throws {
        let cacheFile = tempDir.appendingPathComponent("parse-cache.json")
        let file = tempDir.appendingPathComponent("session.jsonl")
        try makeAssistantLine(id: "m1", model: "claude-opus-4-7", input: 100, output: 50, timestamp: "2026-05-28T12:00:00.000Z")
            .write(to: file, atomically: true, encoding: .utf8)

        _ = SessionReader.readUsage(from: [file], pricing: stubPricing)
        SessionReader.flushPersistForTesting()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path), "cache file should be written")
        XCTAssertGreaterThan(try Data(contentsOf: cacheFile).count, 0)
    }

    // Simulate a process restart: wipe in-memory state, then a same-mtime file serves
    // stale cached tokens, proving the disk cache was loaded rather than re-parsed.
    func testReusesDiskCacheAcrossRestart() throws {
        let cacheFile = tempDir.appendingPathComponent("parse-cache.json")
        let file = tempDir.appendingPathComponent("session.jsonl")
        let mtime = Date(timeIntervalSince1970: 5_000)

        try makeAssistantLine(id: "m1", model: "claude-opus-4-7", input: 100, output: 50, timestamp: "2026-05-28T12:00:00.000Z")
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        XCTAssertEqual(SessionReader.readUsage(from: [file], pricing: stubPricing).totals.inputTokens, 100)
        SessionReader.flushPersistForTesting()

        SessionReader.resetCacheForTesting(fileURL: cacheFile)

        try makeAssistantLine(id: "m1", model: "claude-opus-4-7", input: 999, output: 50, timestamp: "2026-05-28T12:00:00.000Z")
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)

        let reloaded = SessionReader.readUsage(from: [file], pricing: stubPricing)
        XCTAssertEqual(reloaded.totals.inputTokens, 100, "should serve the disk-cached value, not re-parse")
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

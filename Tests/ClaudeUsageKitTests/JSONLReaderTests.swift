import XCTest
@testable import ClaudeUsageKit

final class JSONLReaderTests: XCTestCase {

    func testParseDateHandlesFractionalAndPlainSeconds() throws {
        let withFrac = try XCTUnwrap(JSONLReader.parseDate(from: "2026-05-28T12:00:00.500Z"))
        let plain = try XCTUnwrap(JSONLReader.parseDate(from: "2026-05-28T12:00:00Z"))
        XCTAssertEqual(withFrac.timeIntervalSince1970 - plain.timeIntervalSince1970, 0.5, accuracy: 0.001)
    }

    // A non-UTC offset timestamp resolves to the same instant as its UTC equivalent.
    func testParseDateHandlesOffsetTimestamps() throws {
        let utc = try XCTUnwrap(JSONLReader.parseDate(from: "2026-05-28T12:00:00Z"))
        let offset = try XCTUnwrap(JSONLReader.parseDate(from: "2026-05-28T14:00:00+02:00"))
        XCTAssertEqual(utc.timeIntervalSince1970, offset.timeIntervalSince1970, accuracy: 0.5)
    }

    // The byte-level assistant prefilter must not drop real assistant usage lines,
    // even when other lines contain the word "assistant" in their content.
    func testParseFileKeepsAssistantLinesAndSkipsOthers() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JSONLReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let userLine = #"{"type":"user","message":{"role":"user","content":"tell the assistant to stop"}}"#
        let assistantLine = #"{"type":"assistant","timestamp":"2026-05-28T12:00:00.000Z","message":{"role":"assistant","id":"m1","model":"claude-opus-4-7","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        let file = dir.appendingPathComponent("s.jsonl")
        try (userLine + "\n" + assistantLine + "\n").write(to: file, atomically: true, encoding: .utf8)

        var models: [String] = []
        JSONLReader.parseFile(file) { _, _, usage, model, _ in
            models.append(model)
            XCTAssertEqual(usage.input_tokens, 100)
        }
        XCTAssertEqual(models, ["claude-opus-4-7"])
    }
}

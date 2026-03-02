import XCTest
@testable import ClaudeUsageKit

final class FileCostInfoTests: XCTestCase {

    func testReadCostInfoFromValidFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("test-session.jsonl")
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":200,"cache_read_input_tokens":100}},"timestamp":"2026-03-01T12:00:00Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":800,"output_tokens":300,"cache_creation_input_tokens":0,"cache_read_input_tokens":50}},"timestamp":"2026-03-01T12:01:00Z"}"#,
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let info = SessionFileReader.readCostInfo(at: file)
        XCTAssertNotNil(info)
        // 1000+500+200+100 + 800+300+0+50 = 2950
        XCTAssertEqual(info?.totalTokens, 2950)
        XCTAssertTrue(info!.estimatedCost > 0)
    }

    func testReadCostInfoReturnsNilForEmptyFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("empty.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(SessionFileReader.readCostInfo(at: file))
    }

    func testReadCostInfoCachesByMtime() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("cached.jsonl")
        let line = #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-01T12:00:00Z"}"#
        try line.write(to: file, atomically: true, encoding: .utf8)

        let first = SessionFileReader.readCostInfo(at: file)
        let second = SessionFileReader.readCostInfo(at: file)
        XCTAssertEqual(first?.totalTokens, second?.totalTokens)
        XCTAssertEqual(first?.estimatedCost, second?.estimatedCost)
    }
}

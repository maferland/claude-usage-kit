import Foundation

/// Low-level JSONL line parsing for Claude Code session files.
public enum JSONLReader {

    // MARK: - JSONL structures

    struct Entry: Decodable {
        let type: String?
        let message: Message?
        let timestamp: String?
    }

    struct Message: Decodable {
        let role: String?
        let model: String?
        let id: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    // MARK: - Timestamp handling

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// Convert ISO 8601 UTC timestamp to local date string (yyyy-MM-dd)
    static func localDate(from timestamp: String) -> String? {
        guard let date = parseDate(from: timestamp) else { return nil }
        return localDateFormatter.string(from: date)
    }

    /// Parse ISO 8601 timestamp into Date
    static func parseDate(from timestamp: String) -> Date? {
        isoFormatter.date(from: timestamp) ?? isoFormatterNoFrac.date(from: timestamp)
    }

    // MARK: - File discovery

    static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    static func findJSONLFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files
    }

    // MARK: - Line parsing

    /// Parse a single JSONL file and call the handler for each assistant entry with usage data.
    static func parseFile(
        _ url: URL,
        decoder: JSONDecoder = JSONDecoder(),
        handler: (Entry, Message, Usage, String, String) -> Void
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8) else { continue }

            guard let entry = try? decoder.decode(Entry.self, from: lineData) else { continue }

            guard entry.type == "assistant",
                  let msg = entry.message,
                  msg.role == "assistant",
                  let usage = msg.usage,
                  let model = msg.model,
                  model != "<synthetic>",
                  let timestamp = entry.timestamp else { continue }

            guard let dateStr = localDate(from: timestamp) else { continue }

            handler(entry, msg, usage, model, dateStr)
        }
    }
}

<div align="center">
<h1>ClaudeUsageKit</h1>

<p>Swift package for reading Claude Code session costs from local JSONL files</p>
</div>

---

Parses `~/.claude/projects/` session files, resolves per-model pricing from [LiteLLM](https://github.com/BerriAI/litellm) (with 24h disk cache and hardcoded fallback), and returns token counts + cost breakdowns.

Inspired by [ccusage](https://github.com/ryoppippi/ccusage).

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/maferland/claude-usage-kit", from: "1.0.0")
]
```

Then add `ClaudeUsageKit` to your target dependencies:

```swift
.product(name: "ClaudeUsageKit", package: "claude-usage-kit")
```

## Usage

### Per-file cost lookup

```swift
import ClaudeUsageKit

let url = URL(fileURLWithPath: "~/.claude/projects/.../session.jsonl")
if let info = SessionFileReader.readCostInfo(at: url) {
    print("Tokens: \(info.totalTokens), Cost: $\(info.estimatedCost)")
}
```

Results are cached by file mtime — repeated calls for unchanged files are free.

### Daily aggregates

```swift
let response = try SessionReader.readUsage()
let data = UsageData.from(response: response)
print("Today: $\(data.todayCost), This week: $\(data.weekTotal)")
```

### Per-session breakdown

```swift
let sessions = try SessionFileReader.readAllSessions()
for session in sessions {
    print("\(session.sessionId): $\(session.totalCost) (\(session.primaryModel ?? "unknown"))")
}
```

## Requirements

- macOS 14+
- Swift 5.9+

## License

[MIT](LICENSE)

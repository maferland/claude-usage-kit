# ClaudeUsageKit

Swift package that reads Claude Code session JSONL files and calculates token usage + cost.

## Dev

```bash
make build   # swift build
make test    # swift test
make clean   # swift package clean
```

## Architecture

- `Sources/ClaudeUsageKit/Reading/` — JSONL parsing, session/file readers
- `Sources/ClaudeUsageKit/Models/` — data types (TokenBucket, FileCostInfo, SessionUsage, DailyUsage)
- `Sources/ClaudeUsageKit/Pricing/` — LiteLLM price fetching + caching + fallback rates
- `Tests/ClaudeUsageKitTests/` — unit tests

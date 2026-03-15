# Contributing to WhisprPro

## Development Setup

See [README.md](README.md) for build instructions.

## Swift Best Practices

This project follows Apple's Swift conventions and modern best practices.

### Architecture

- **MVVM** with `@Observable` (not `ObservableObject`)
- **SwiftData** for persistence (not Core Data)
- **Swift Structured Concurrency** — `async/await`, `actor` for thread safety
- **SwiftUI** declarative UI with `NavigationSplitView`

### Code Style

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `final class` unless inheritance is needed
- Prefer `struct` over `class` for value types
- Use `@MainActor` for UI-bound code
- Use `actor` for shared mutable state (e.g., `TranscriptionService`)
- Use `nonisolated` for actor methods that don't access mutable state
- Mark classes as `Sendable` when thread-safe

### Naming

- Types: `UpperCamelCase` — `TranscriptionService`, `WhisperSegment`
- Methods/properties: `lowerCamelCase` — `loadModel()`, `isDownloaded`
- Enums cases: `lowerCamelCase` — `.transcribing`, `.completed`
- Boolean properties: read as assertions — `isPlaying`, `isEdited`

### Error Handling

- Define domain-specific error enums conforming to `LocalizedError`
- Provide `errorDescription` for user-facing messages
- Use `throws` for recoverable errors, not force-unwrapping

### Testing

- Use Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- In-memory `ModelContainer` for SwiftData tests
- Test file mirrors source: `WhisprPro/Services/X.swift` → `WhisprProTests/Services/XTests.swift`

### Git

- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`
- One logical change per commit
- Keep commits small and focused

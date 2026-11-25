# Suite Core

The library every app of Love Suite shares: where the settings live and how the apps talk to
each other, settings profiles, updates. No app of its own; what only the apps handling files need is in
`suite-files`.

Apps depend on it within their version of the suite:

```swift
.package(url: "https://github.com/love-suite/suite-core", .upToNextMinor(from: "27.1.0"))
```

Development: `swift build`, `swift test` (Swift 6.4.2, macOS 13 or later).

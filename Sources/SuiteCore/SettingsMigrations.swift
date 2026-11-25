import Foundation

/// A change to saved settings between two released versions, converted by the update rather than by code
/// every launch keeps running: each app lists its steps, each for the version that brought the change, and
/// gives them to its `SuiteUpdater`, which runs, at the first launch of a new version, the steps of every
/// version after the one that last ran, once. A fresh install has nothing to convert.
public struct SettingsMigration {
    /// The released version that brought the change (27.2, 27.2.1).
    public let version: String
    public let run: (UserDefaults) -> Void

    public init(version: String, run: @escaping (UserDefaults) -> Void) {
        self.version = version
        self.run = run
    }
}

public enum SettingsMigrations {
    /// Where an app notes the version whose settings it last brought up to date.
    public static let versionKey = "SuiteSettingsVersion"

    /// Runs the steps after `defaults`' noted version up to `current`, oldest first, then notes `current`.
    /// The first time (nothing noted), nothing runs.
    public static func run(_ steps: [SettingsMigration], current: String, defaults: UserDefaults = .standard) {
        let now = SuiteVersion(current)
        guard let noted = defaults.string(forKey: versionKey) else {
            defaults.set(now.release, forKey: versionKey)
            return
        }
        let last = SuiteVersion(noted)
        for step in steps.sorted(by: { SuiteVersion($0.version) < SuiteVersion($1.version) }) {
            let version = SuiteVersion(step.version)
            if last < version && version <= now { step.run(defaults) }
        }
        if last < now { defaults.set(now.release, forKey: versionKey) }
    }
}

/// A version of the suite: AA.Y or AA.Y.Z, a development build's "-dev.N" left out (27.1-dev.3 is 27.1).
public struct SuiteVersion: Comparable, Sendable {
    public let parts: [Int]

    public init(_ text: String) {
        let release = text.split(separator: "-").first.map(String.init) ?? text
        var parts = release.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        self.parts = parts
    }

    /// As written in a tag: 27.1, 27.1.1.
    public var release: String {
        (parts[2] == 0 ? parts.prefix(2) : parts.prefix(3)).map(String.init).joined(separator: ".")
    }

    public static func < (a: SuiteVersion, b: SuiteVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

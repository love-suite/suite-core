import Foundation

/// A named set of the suite's settings (Explorer, Bar, Clipboard, Viewer, Bindings, Launcher), saved as a file on this Mac or
/// in iCloud Drive, to switch between configurations or bring one to another Mac. Preferences and the
/// windows macOS remembers by name (Viewer's, Clipboard's history), which it keeps on screen when they come
/// back; not panels' last folders, nor what Explorer keeps to put this Mac back as it was (the hidden Dock's
/// previous settings), nor what an app reports about itself. Each app's settings carry the version whose
/// format they have (`versions`): loaded into a later version of that app, its update converts them
/// (`SettingsMigrations`).
public struct SettingsProfile {
    public var name: String
    public var modified: Date
    /// Domain (bundle id) → its settings.
    public var settings: [String: [String: Any]]
    /// Domain → the version of that app whose format its settings have (27.1).
    public var versions: [String: String]

    public init(name: String, modified: Date = Date(), settings: [String: [String: Any]],
                versions: [String: String] = [:]) {
        self.name = name
        self.modified = modified
        self.settings = settings
        self.versions = versions
    }

    /// The suite's apps, whose settings a profile holds.
    public static let domains = ["local.suite.explorer", "local.suite.desktop", "local.suite.bar", "local.suite.clipboard",
                                 "local.suite.viewer", "local.suite.bindings", "local.suite.launcher"]

    /// The key under which Explorer remembers the profile last loaded or saved; not part of profiles.
    public static let currentKey = "CurrentProfile"

    /// The system's keys, and what Explorer reports to Suite Settings about itself (`Status…`).
    private static let systemPrefixes = ["NS", "Apple", "com.apple.", "WebKit", "Status"]
    private static let stateKeys: Set<String> = [
        currentKey, "DockSettingsBeforeHiding", "BarRecentApps", "hasLaunchedBefore", "canPaste",
        "loginStatus", "hasExplainedAccessibility", "ExplorerSession", "SuiteGuardRegisteredBuild",
        // What Desktop and Clipboard keep of this Mac's own settings while they replace Finder's desktop and
        // Spotlight's history, and Desktop's own state.
        "FinderDesktopBeforeHiding", "SpotlightHistoryBefore", "FinderSyncRecord", "FinderRestartedByDesktop",
        "LoginItemRegistered",
        SettingsMigrations.versionKey,
    ]

    /// Where macOS keeps a named window's frame.
    public static let windowFramePrefix = "NSWindow Frame "

    /// A preference worth carrying, or a window's frame; not the system's nor the apps' own state.
    public static func isPortable(_ key: String) -> Bool {
        if key.hasPrefix(windowFramePrefix) { return true }
        return !stateKeys.contains(key) && !systemPrefixes.contains { key.hasPrefix($0) }
    }

    /// The current settings of `domains` (domain → its defaults' values), with the version each app noted
    /// its settings are at.
    public static func capture(name: String, from domains: [String: [String: Any]]) -> SettingsProfile {
        var settings: [String: [String: Any]] = [:]
        var versions: [String: String] = [:]
        for (domain, values) in domains {
            let portable = values.filter { isPortable($0.key) }
            if !portable.isEmpty { settings[domain] = portable }
            if let version = values[SettingsMigrations.versionKey] as? String { versions[domain] = version }
        }
        return SettingsProfile(name: name, settings: settings, versions: versions)
    }

    /// What to write in each domain to bring it to this profile: its values, and the portable keys it has
    /// now that the profile doesn't, removed (back to their defaults).
    public func changes(from current: [String: [String: Any]]) -> [String: (set: [String: Any], remove: [String])] {
        var result: [String: (set: [String: Any], remove: [String])] = [:]
        for domain in Set(current.keys).union(settings.keys) {
            var wanted = settings[domain] ?? [:]
            let removed = (current[domain] ?? [:]).keys.filter { Self.isPortable($0) && wanted[$0] == nil }
            // The app converts them, if they are an earlier version's, at its next launch or when told.
            if !wanted.isEmpty, let version = versions[domain] { wanted[SettingsMigrations.versionKey] = version }
            if !wanted.isEmpty || !removed.isEmpty { result[domain] = (wanted, removed.sorted()) }
        }
        return result
    }

    /// Puts `keys` back as `values` holds them, or to their defaults (removed) where it doesn't: a part of the
    /// settings restored from a profile, or to how they first were (`values` nil).
    public static func restore(_ keys: [String], in defaults: UserDefaults, from values: [String: Any]?) {
        for key in keys {
            if let value = values?[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    // MARK: File

    public func data() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "name": name, "modified": modified, "settings": settings, "versions": versions,
        ] as [String: Any], format: .xml, options: 0)
    }

    public static func read(_ data: Data) throws -> SettingsProfile {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["name"] as? String,
              let settings = plist["settings"] as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return SettingsProfile(name: name, modified: plist["modified"] as? Date ?? Date(), settings: settings,
                               versions: plist["versions"] as? [String: String] ?? [:])
    }
}

/// Where profiles are kept: on this Mac, or in iCloud Drive for every Mac on the account.
public enum ProfileLocation: String, CaseIterable, Sendable {
    case thisMac, iCloudDrive

    public var title: String { self == .thisMac ? "This Mac" : "iCloud Drive" }

    public func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch self {
        case .thisMac:
            return home.appendingPathComponent("Library/Application Support/Explorer/Profiles", isDirectory: true)
        case .iCloudDrive:
            return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Explorer/Profiles",
                                               isDirectory: true)
        }
    }
}

/// A profile file found in one of the locations.
public struct ProfileFile: Equatable, Sendable {
    public var url: URL
    public var name: String
    public var location: ProfileLocation
    public var modified: Date
}

/// Lists, saves, moves and removes profile files.
public struct ProfileStore {
    public var home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    /// Every profile in both locations, by name.
    public func list() -> [ProfileFile] {
        ProfileLocation.allCases.flatMap { location -> [ProfileFile] in
            let folder = location.folder(home: home)
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "plist" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), let profile = try? SettingsProfile.read(data) else { return nil }
                return ProfileFile(url: url, name: profile.name, location: location, modified: profile.modified)
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A file name from a profile's name: what a file name can't hold becomes a dash.
    public static func fileName(for name: String) -> String {
        let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }
        let base = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Profile" : base) + ".plist"
    }

    /// Saves `profile` in `location`, replacing a profile of the same name there; returns its file.
    @discardableResult
    public func save(_ profile: SettingsProfile, in location: ProfileLocation) throws -> URL {
        let folder = location.folder(home: home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Self.fileName(for: profile.name))
        try profile.data().write(to: url, options: .atomic)
        return url
    }

    public func read(_ file: ProfileFile) throws -> SettingsProfile {
        try SettingsProfile.read(Data(contentsOf: file.url))
    }

    /// Moves a profile to the other location; returns its new file.
    @discardableResult
    public func move(_ file: ProfileFile, to location: ProfileLocation) throws -> URL {
        let saved = try save(read(file), in: location)
        if saved.standardizedFileURL != file.url.standardizedFileURL {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        }
        return saved
    }

    /// Removes a profile by moving its file to the Trash.
    public func remove(_ file: ProfileFile) throws {
        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
    }
}

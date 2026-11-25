import Foundation

/// Where Explorer's settings live: its own defaults in Explorer, and the same domain, by name, in the
/// Suite Settings app, which writes them for it (`local.suite.explorer`).
public enum SuiteDefaults {
    public static let explorerDomain = "local.suite.explorer"

    /// Explorer's settings, read and written from whichever app of the suite.
    nonisolated(unsafe) public static var explorer: UserDefaults = .standard

    /// Called first thing by an app other than Explorer that reads or writes Explorer's settings.
    public static func useExplorerDomain() {
        if Bundle.main.bundleIdentifier != explorerDomain, let suite = UserDefaults(suiteName: explorerDomain) {
            explorer = suite
        }
    }
}

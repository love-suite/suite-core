import AppKit
import UniformTypeIdentifiers

/// Viewer, the picture and PDF viewer, as the other apps of the suite see it.
public enum ViewerApp {
    public static let bundleID = "local.suite.viewer"

    /// A picture Viewer shows. PDFs and icons are images to the system but documents to people; they keep
    /// their own apps.
    public static func showsPicture(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .pdf) && type != .icns
    }

    /// A PDF, which Viewer shows too.
    public static func showsPDF(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .pdf)
    }
}

/// Clipboard, the clipboard history, as the other apps of the suite see it.
public enum ClipboardApp {
    public static let bundleID = "local.suite.clipboard"

    /// Clipboard's own defaults, which its settings tab writes.
    public static var defaults: UserDefaults { UserDefaults(suiteName: bundleID) ?? .standard }

    /// Whether Clipboard runs at all (Settings › Clipboard).
    public static var isEnabled: Bool {
        defaults.object(forKey: "isEnabled") as? Bool ?? true
    }
}

/// Dock, the suite's Dock in place of the system one, as the other apps see it.
public enum SuiteBarApp {
    public static let bundleID = "local.suite.bar"
}

/// Launcher, the app grid in place of Launchpad, as the other apps see it (Bar's Launcher tile).
public enum LauncherApp {
    public static let bundleID = "local.suite.launcher"

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Opens the grid: starts Launcher if needed, then tells it to show.
    public static func open() {
        if isRunning {
            LauncherMessage.open.post()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { LauncherMessage.open.post() }
        }
    }
}

/// What Launcher and the other apps say to each other, as distributed notifications.
public enum LauncherMessage: String, CaseIterable, Sendable {
    /// To Launcher: show the grid.
    case open
    /// To Launcher: its settings were changed (Suite Settings); read them again.
    case settingsDidChange

    public var name: Notification.Name { Notification.Name("local.suite.launcher." + rawValue) }

    public func post(_ userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo,
                                                                     deliverImmediately: true)
    }

    @discardableResult
    public func observe(_ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
}

/// Bindings, the keyboard shortcuts app, as the other apps see it: Explorer starts it and tells it where the
/// keyboard is in Explorer, Suite Settings edits its rules.
public enum BindingsApp {
    public static let bundleID = "local.suite.bindings"

    /// Bindings' own defaults, which its settings tab writes.
    public static var defaults: UserDefaults { UserDefaults(suiteName: bundleID) ?? .standard }

    /// Whether Bindings runs at all (Settings › Bindings).
    public static var isEnabled: Bool {
        defaults.object(forKey: "isEnabled") as? Bool ?? true
    }

    public static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Starts Bindings in the background, unless it is running already or not installed.
    public static func launch(arguments: [String] = []) {
        guard let url = appURL, !isRunning else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Asks Bindings to put itself in the Accessibility list and open it; started for that if it isn't running.
    public static func requestAccessibility() {
        isRunning ? BindingsMessage.requestAccessibility.post() : launch(arguments: ["--request-accessibility"])
    }
}

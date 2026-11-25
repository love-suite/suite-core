import AppKit

/// What Suite Settings asks of Explorer, and what Explorer tells it. The settings themselves are written
/// in Explorer's defaults (`SuiteDefaults`); Explorer is then told to apply them, and what only Explorer
/// can do (check for updates, ask for Accessibility, empty the Trash, reopen) is asked of it.
public enum ExplorerLink {
    public enum Command: String, CaseIterable, Sendable {
        /// Settings were written: read them again and apply them, as a change made in Explorer would.
        case applySettings
        case checkForUpdates
        /// Ask for Accessibility, which shortens other apps' windows above the Dock.
        case allowWindowFitting
        case emptyTrash
        case relaunch
        /// Reopen without its windows of last time (`--relaunch --background`, after a build).
        case relaunchInBackground
        /// Write down what Settings shows about Explorer (its status keys) and say so.
        case reportStatus
    }

    /// To Explorer: a command, as the notification's object.
    public static let commandNotification = Notification.Name("local.suite.explorer.command")
    /// To Suite Settings: Explorer's settings or status changed; redraw.
    public static let explorerDidChange = Notification.Name("local.suite.settings.explorerDidChange")
    /// To Suite Settings: show a tab (`"tab"` in the user info), from Explorer's menus.
    public static let showNotification = Notification.Name("local.suite.settings.show")

    public static func send(_ command: Command) {
        DistributedNotificationCenter.default().postNotificationName(commandNotification, object: command.rawValue,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    private static var pendingApply: DispatchWorkItem?

    /// After a setting is written: Explorer applies it a moment later, once for a burst of changes.
    public static func settingsChanged() {
        pendingApply?.cancel()
        let work = DispatchWorkItem {
            // Written out to the preferences daemon before Explorer is told to read them.
            CFPreferencesAppSynchronize(SuiteDefaults.explorerDomain as CFString)
            send(.applySettings)
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: What Explorer reports

    public enum StatusKey {
        public static let updaterState = "StatusUpdaterState"
        public static let canSetDefaultViewer = "StatusCanSetDefaultViewer"
        public static let windowFittingAllowed = "StatusWindowFittingAllowed"
    }

    public static var updaterState: String { SuiteDefaults.explorer.string(forKey: StatusKey.updaterState) ?? "" }
    public static var canSetDefaultViewer: Bool {
        SuiteDefaults.explorer.object(forKey: StatusKey.canSetDefaultViewer) as? Bool ?? true
    }
    public static var windowFittingAllowed: Bool { SuiteDefaults.explorer.bool(forKey: StatusKey.windowFittingAllowed) }

    /// Explorer's own Info.plist: its version, build, and whether it carries the update key.
    private static var explorerInfo: [String: Any] {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SuiteDefaults.explorerDomain),
              let info = Bundle(url: url)?.infoDictionary else { return [:] }
        return info
    }

    public static var explorerVersion: String { explorerInfo["CFBundleShortVersionString"] as? String ?? "?" }
    public static var explorerBuild: String { explorerInfo["CFBundleVersion"] as? String ?? "?" }
    public static var hasUpdateKey: Bool { !((explorerInfo["ExplorerUpdatePublicKey"] as? String) ?? "").isEmpty }
}

/// Explorer as another app of the suite opens it: by bundle id, never through its code.
extension ExplorerLink {
    public static var explorerURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SuiteDefaults.explorerDomain)
    }

    /// Starts Explorer, or brings it to the front as a click on its icon does (a window if none is open).
    public static func activate() {
        guard let app = explorerURL else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens folders in Explorer windows (the Trash's folder shows Explorer's Trash), and files as
    /// Explorer opens them. Without Explorer, the system opens them.
    public static func open(_ urls: [URL]) {
        guard let app = explorerURL else {
            urls.forEach { NSWorkspace.shared.open($0) }
            return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Asks Explorer to open files as it opens them (pictures and PDFs to Viewer, the rest in their app).
    public static let openFilesNotification = Notification.Name("local.suite.explorer.openFiles")

    /// Opens files as Explorer does when it runs, as the system does otherwise.
    public static func openFiles(_ urls: [URL]) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: SuiteDefaults.explorerDomain).isEmpty
        else {
            urls.forEach { NSWorkspace.shared.open($0) }
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            openFilesNotification, object: nil, userInfo: ["paths": urls.map(\.path)], deliverImmediately: true)
    }

    /// The files of an `openFilesNotification`.
    public static func files(of notification: Notification) -> [URL] {
        (notification.userInfo?["paths"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// Shows the items selected in their folder, in the folder viewer (Explorer while it stands in for
    /// Finder).
    public static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// Suite Settings, as the other apps open it.
public enum SuiteSettingsApp {
    public static let bundleID = "local.suite.settings"

    /// Opens Suite Settings on `tab`; false if it isn't installed.
    @discardableResult
    public static func show(tab: String? = nil) -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            DistributedNotificationCenter.default().postNotificationName(
                ExplorerLink.showNotification, object: nil, userInfo: tab.map { ["tab": $0] }, deliverImmediately: true)
            running.activate()
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = tab.map { ["--tab", $0] } ?? []
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}

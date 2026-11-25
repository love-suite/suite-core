import AppKit
import Security

/// The strings of SuiteCore's catalog, from its resource bundle in the app (`make-app.sh` copies it);
/// English without it. Not `Bundle.module`, which stops the app when the bundle is missing.
let suiteCoreBundle: Bundle = Bundle.main.url(forResource: "SuiteCore_SuiteCore", withExtension: "bundle")
    .flatMap(Bundle.init(url:)) ?? .main

func SL(_ key: String) -> String { NSLocalizedString(key, bundle: suiteCoreBundle, comment: "") }

/// Keeps the app it runs in up to date from its own releases on GitHub (or at another web address): each
/// app of the suite has its own. A minute after launch and every six hours it reads `update.json`; a newer
/// build is checked against the publisher's signature, unpacked, and the app is replaced and relaunched,
/// without asking once it isn't in use (`isBusy`), or after asking, as set. A `quiet` updater (an agent
/// without windows) never asks and never shows a dialog.
public final class SuiteUpdater {
    public static let didChange = Notification.Name("SuiteUpdaterDidChange")

    public enum State: Equatable {
        case idle, checking, upToDate(Date), available(UpdateFeed), installing, failed(String)
    }

    public private(set) var state = State.idle {
        didSet { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    /// The app's name in dialogs.
    public let appName: String
    private let defaults: UserDefaults
    private let isBusy: () -> Bool
    private let quiet: Bool
    private let relaunch: () -> Void
    /// The changes to this app's saved settings between released versions (`SettingsMigrations`).
    private let migrations: [SettingsMigration]

    /// `defaults`: where the update settings live (the app's own), and the settings `migrations` convert;
    /// `isBusy`: true while replacing the app
    /// would be under the user's feet (a window open, by default); `relaunch`: how the new copy starts.
    public init(appName: String, defaults: UserDefaults = .standard,
                isBusy: @escaping () -> Bool = { NSApp?.windows.contains { $0.isVisible } ?? false },
                quiet: Bool = false, migrations: [SettingsMigration] = [],
                relaunch: @escaping () -> Void = { AppRelauncher.relaunch() }) {
        self.migrations = migrations
        self.appName = appName
        self.defaults = defaults
        self.isBusy = isBusy
        self.quiet = quiet
        self.relaunch = relaunch
    }

    public var settings: UpdateSettings {
        get { UpdateSettings.load(from: defaults) }
        set {
            newValue.save(to: defaults)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
            schedule()
        }
    }

    /// The app a release may replace: this one alone, each app of the suite having its own releases.
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    /// The publisher's public key, put in the app by `scripts/make-app.sh`; without it the app can't
    /// tell a genuine release, so it doesn't update.
    public var publicKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ExplorerUpdatePublicKey") as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
    }

    public var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    public var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    private var timer: Timer?
    private var idleTimer: Timer?
    private let queue = DispatchQueue(label: "SuiteCore.SuiteUpdater", qos: .utility)

    /// At launch: brings the saved settings up to this version (after an update), then checks for the next.
    public func start() {
        bringSettingsUpToDate()
        schedule()
    }

    /// Converts the saved settings from the version they were noted at (an update, or a profile of an
    /// earlier version just loaded) to this one. Apps call it when told their settings were written.
    public func bringSettingsUpToDate() {
        SettingsMigrations.run(migrations, current: currentVersion, defaults: defaults)
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard settings.checksAutomatically, publicKey != nil else { return }
        // A minute after launch, then every six hours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.timer == nil else { return }
            self.check(userInitiated: false)
            self.timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
                self?.check(userInitiated: false)
            }
        }
    }

    // MARK: Checking

    public func check(userInitiated: Bool) {
        guard state != .checking, state != .installing else { return }
        guard let publicKey else {
            state = .failed(SL("This build has no update key, so it can't check releases."))
            return
        }
        guard let feedURL = settings.feedURL(
            builtIn: Bundle.main.object(forInfoDictionaryKey: "ExplorerUpdateFeed") as? String)
        else {
            state = .failed(SL("No release published yet."))
            if userInitiated { alert(SL("Couldn't check for updates"), describeState()) }
            return
        }
        state = .checking
        queue.async { [weak self] in
            let result = Result { try UpdateFeed.decode(Self.read(feedURL)) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    // No release folder yet is not a failure worth a dialog.
                    self.state = .failed(Self.describe(error, reading: feedURL))
                    if userInitiated { self.alert(SL("Couldn't check for updates"), self.describeState()) }
                case .success(let feed) where !feed.isNewer(thanBuild: self.currentBuild):
                    self.state = .upToDate(Date())
                    if userInitiated {
                        self.alert(String(format: SL("%@ is up to date"), self.appName),
                                   String(format: SL("Version %@ (%d)."), self.currentVersion, self.currentBuild))
                    }
                case .success(let feed):
                    self.state = .available(feed)
                    if self.quiet || (self.settings.installsAutomatically && !userInitiated) {
                        self.installWhenIdle(feed, from: feedURL, publicKey: publicKey)
                    } else {
                        self.offer(feed, from: feedURL, publicKey: publicKey)
                    }
                }
            }
        }
    }

    private func offer(_ feed: UpdateFeed, from feedURL: URL, publicKey: String) {
        guard !quiet else { return installWhenIdle(feed, from: feedURL, publicKey: publicKey) }
        let alert = NSAlert()
        alert.messageText = String(format: SL("%1$@ %2$@ is available"), appName, feed.version)
        alert.informativeText = (feed.notes.isEmpty ? "" : feed.notes + "\n\n")
            + String(format: SL("You have %1$@ (%2$d). %3$@ reopens after the update."),
                     currentVersion, currentBuild, appName)
        alert.addButton(withTitle: SL("Install and Relaunch"))
        alert.addButton(withTitle: SL("Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { install(feed, from: feedURL, publicKey: publicKey) }
    }

    /// Without asking, but not under the user's feet: once the app isn't in use (`isBusy`).
    private func installWhenIdle(_ feed: UpdateFeed, from feedURL: URL, publicKey: String) {
        idleTimer?.invalidate()
        guard isBusy() else {
            install(feed, from: feedURL, publicKey: publicKey)
            return
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard let self, !self.isBusy() else { return }
            timer.invalidate()
            self.install(feed, from: feedURL, publicKey: publicKey)
        }
    }

    // MARK: Installing

    public func install(_ feed: UpdateFeed, from feedURL: URL, publicKey: String) {
        guard state != .installing else { return }
        state = .installing
        let destination = Bundle.main.bundleURL.deletingLastPathComponent()
        let bundleID = self.bundleID
        queue.async { [weak self] in
            let result = Result { try Self.prepare(feed, from: feedURL, publicKey: publicKey, near: destination,
                                                   bundleID: bundleID) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.state = .failed(String(format: SL("The update couldn't be installed: %@"), error.localizedDescription))
                case .success(let app):
                    do {
                        let target = destination.appendingPathComponent(app.lastPathComponent)
                        if FileManager.default.fileExists(atPath: target.path) {
                            _ = try FileManager.default.replaceItemAt(target, withItemAt: app)
                        } else {
                            try FileManager.default.moveItem(at: app, to: target)
                        }
                        self.relaunch()
                    } catch {
                        self.state = .failed(String(format: SL("The update couldn't be installed: %@"), error.localizedDescription))
                    }
                }
            }
        }
    }

    enum Failure: LocalizedError {
        case noArchive, unexpectedContents(String), invalidSignature(String)

        var errorDescription: String? {
            switch self {
            case .noArchive: return "the release has no archive this app can read."
            case .unexpectedContents(let what): return "the archive holds something unexpected (\(what))."
            case .invalidSignature(let what): return "\(what) isn't signed properly."
            }
        }
    }

    /// Reads and checks the archive, then unpacks it next to the installed app: the one app it holds,
    /// this app's new copy, verified, ready to take its place.
    private static func prepare(_ feed: UpdateFeed, from feedURL: URL, publicKey: String,
                                near destination: URL, bundleID: String) throws -> URL {
        guard let archiveURL = feed.archiveURL(relativeTo: feedURL) else { throw Failure.noArchive }
        let archive = try read(archiveURL)
        try UpdateSignature.verify(archive, signature: feed.signature, publicKey: publicKey)

        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination,
                                 create: true)
        let zip = staging.appendingPathComponent("update.zip")
        try archive.write(to: zip)
        let unpacked = staging.appendingPathComponent("apps", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.unexpectedContents("it couldn't be unpacked") }

        let apps = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first, Bundle(url: app)?.bundleIdentifier == bundleID else {
            throw Failure.unexpectedContents(apps.map(\.lastPathComponent).joined(separator: ", "))
        }
        // Untouched since it was signed.
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures
                                                              | kSecCSStrictValidate), nil) == errSecSuccess
        else { throw Failure.invalidSignature(app.lastPathComponent) }
        return app
    }

    // MARK: Reading

    /// A web address is fetched; a file (an address typed in the settings, for testing) is read.
    private static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else {
            var result: Result<Data, Error> = .failure(URLError(.unknown))
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                    result = .success(data)
                } else {
                    result = .failure(error ?? URLError(.badServerResponse))
                }
                done.signal()
            }.resume()
            done.wait()
            return try result.get()
        }
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadNoSuchFile))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readable in
            result = Result { try Data(contentsOf: readable) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    private static func describe(_ error: Error, reading url: URL) -> String {
        if url.isFileURL, (error as NSError).domain == NSCocoaErrorDomain,
           [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains((error as NSError).code) {
            return String(format: SL("No release at %@."), url.path)
        }
        return String(format: SL("Couldn't read the latest release: %@"), error.localizedDescription)
    }

    /// One line for the settings.
    public func describeState() -> String {
        switch state {
        case .idle: return publicKey == nil ? SL("This build has no update key, so it can't check releases.") : ""
        case .checking: return SL("Checking")
        case .upToDate(let date):
            return String(format: SL("Up to date (checked at %@)."),
                          DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
        case .available(let feed): return String(format: SL("Version %@ is available."), feed.version)
        case .installing: return SL("Installing")
        case .failed(let message): return message
        }
    }

    private func alert(_ title: String, _ text: String) {
        guard !quiet else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

import AppKit

public enum AppRelauncher {
    /// Set while the app quits only to open again (an update, Reopen): it is coming straight back.
    public private(set) static var isRelaunching = false

    /// Opens a new copy of the app (the one now on disk, after an update), which waits for this one to be
    /// gone and takes over, then quits. The new copy is started by macOS as an app of its own: a process
    /// this app started itself would be ended with it.
    /// `inBackground`: the new copy doesn't open the windows of last time.
    public static func relaunch(inBackground: Bool = false) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = ["--after", String(ProcessInfo.processInfo.processIdentifier)]
            + (inBackground ? ["--background"] : [])
        // The new copy holds back until this one is gone, so macOS won't report it launched before then:
        // quit once the request is on its way rather than wait for an answer that can't come.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { FileHandle.standardError.write(Data("Relaunch failed: \(error)\n".utf8)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRelaunching = true
            NSApp.terminate(nil)
        }
    }

    /// Started with `--background`: runs without opening the windows of last time; they stay saved for
    /// the next launch until a window is opened.
    public static var isBackgroundLaunch: Bool { CommandLine.arguments.contains("--background") }

    /// The copy that reopened this one (`--after <pid>`), gone once `waitForPreviousCopy()` returns.
    public static var previousCopy: pid_t? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--after"), index + 1 < arguments.count else { return nil }
        return pid_t(arguments[index + 1])
    }

    /// For the new copy: waits (at most 30 seconds) until the copy it replaces, given by `--after <pid>`,
    /// is gone; true if it was asked to.
    @discardableResult
    public static func waitForPreviousCopy() -> Bool {
        guard let pid = previousCopy else { return false }
        let deadline = Date().addingTimeInterval(30)
        while kill(pid, 0) == 0, Date() < deadline { usleep(100_000) }
        return true
    }
}

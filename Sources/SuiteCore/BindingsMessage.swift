import Foundation

/// What Bindings, Explorer and Suite Settings say to each other, as distributed notifications, as
/// Clipboard and Explorer do with `ClipboardMessage`.
public enum BindingsMessage: String, CaseIterable, Sendable {
    /// To Bindings: the rules file changed; read it again.
    case rulesDidChange
    /// To Bindings: its settings were changed (on or off); read them again.
    case settingsDidChange
    /// To Bindings: let every key through (`"paused": true`) while Settings records a chord, or
    /// work again (`false`).
    case setPaused
    /// To Bindings: put itself in the Accessibility list and open it.
    case requestAccessibility
    /// To Suite Settings: Bindings' status (`canListen`) changed.
    case statusDidChange
    /// To Bindings: where the keyboard is in Explorer (`"context"`: an `ExplorerContext` raw value).
    case explorerContextDidChange
    /// To Explorer: Bindings started and wants to know where the keyboard is.
    case requestExplorerContext
    /// To Bindings: read the menus of this running app (`"bundleID"`) into its menu catalog.
    case scanMenus
    /// To Suite Settings: the menu catalog has this app's menus (`"bundleID"`), or couldn't read them
    /// (`"failed": true`).
    case menusDidChange

    public static let contextKey = "context"
    public static let bundleIDKey = "bundleID"
    public static let failedKey = "failed"
    public static let pausedKey = "paused"

    public var name: Notification.Name {
        Notification.Name(BindingsApp.bundleID + "." + rawValue)
    }

    /// Delivered at once, even to an app in the background, which they often are.
    public func post(_ userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo,
                                                                     deliverImmediately: true)
    }

    @discardableResult
    public func observe(_ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
}

/// Where the keyboard is in Explorer, which only Explorer knows (which of its windows is which): it tells
/// Bindings with `BindingsMessage.explorerContextDidChange`, and Bindings' rules can apply there only.
public enum ExplorerContext: String, CaseIterable, Sendable, Codable {
    /// The desktop has the keyboard.
    case desktop
    /// An Explorer window (a folder) is in front.
    case folderWindow
    /// Another of Explorer's windows (Properties, Change Icon).
    case otherWindow

    /// Explorer's bundle id: these places exist only while Explorer is in front.
    public static let bundleID = SuiteDefaults.explorerDomain

    /// Posted by Explorer whenever its key window changes.
    public func post() {
        BindingsMessage.explorerContextDidChange.post([BindingsMessage.contextKey: rawValue])
    }
}

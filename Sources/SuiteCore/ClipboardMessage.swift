import Foundation

/// What Clipboard and Explorer say to each other, as distributed notifications: Explorer's Settings
/// change Clipboard's, and Clipboard's panel opens them.
public enum ClipboardMessage: String, CaseIterable, Sendable {
    /// To Clipboard: settings were changed in Explorer; read them again.
    case settingsDidChange
    /// To Clipboard: delete every item.
    case clearHistory
    /// To Clipboard: register (`"on": true`) or remove its login item.
    case setOpensAtLogin
    /// To Clipboard: put itself in the Accessibility list and open it.
    case requestAccessibility
    /// To Explorer: Clipboard's status (`canPaste`, `loginStatus`) changed.
    case statusDidChange
    /// To Explorer: show the Clipboard tab of Settings.
    case showSettings
    /// To Explorer: Clipboard came into the Dock (its history window opened) or left it.
    case dockPresenceDidChange

    public var name: Notification.Name {
        Notification.Name("local.suite.clipboard." + rawValue)
    }

    /// Delivered at once, even to an app in the background, which both always are.
    public func post(_ userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo,
                                                                     deliverImmediately: true)
    }

    @discardableResult
    public func observe(_ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
}

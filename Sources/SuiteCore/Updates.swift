import CryptoKit
import Foundation

/// What a published release says about itself: `update.json`, next to the archive holding the apps
/// (Explorer, Viewer, Clipboard…), among a GitHub release's files or at another web address.
public struct UpdateFeed: Codable, Equatable, Sendable {
    /// Shown to people: "2026.2".
    public var version: String
    /// Compared: the number of commits on main when it was built, always growing.
    public var build: Int
    /// The archive's file name next to the feed, or a full web address.
    public var archive: String
    /// Ed25519 signature of the archive, base64.
    public var signature: String
    public var notes: String
    public var published: Date?

    public init(version: String, build: Int, archive: String, signature: String, notes: String = "",
                published: Date? = nil) {
        self.version = version
        self.build = build
        self.archive = archive
        self.signature = signature
        self.notes = notes
        self.published = published
    }

    public static func decode(_ data: Data) throws -> UpdateFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UpdateFeed.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// True if this release is newer than the running build.
    public func isNewer(thanBuild current: Int) -> Bool { build > current }

    /// Where the archive is, from where the feed was read.
    public func archiveURL(relativeTo feed: URL) -> URL? {
        if let url = URL(string: archive), url.scheme == "https" { return url }
        guard !archive.contains("/"), !archive.isEmpty, archive != "..", archive != "." else { return nil }
        return feed.deletingLastPathComponent().appendingPathComponent(archive)
    }
}

/// Checks that an archive was signed by the publisher's private key: the app carries the public key, so
/// an archive changed or made by someone else is refused.
public enum UpdateSignature {
    public enum Failure: Error, Equatable { case badKey, badSignature, mismatch }

    public static func verify(_ data: Data, signature: String, publicKey: String) throws {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw Failure.badKey }
        guard let signatureData = Data(base64Encoded: signature) else { throw Failure.badSignature }
        guard key.isValidSignature(signatureData, for: data) else { throw Failure.mismatch }
    }

    /// For the publishing script and the tests: a signature made with a raw private key.
    public static func sign(_ data: Data, privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else { throw Failure.badKey }
        return try key.signature(for: data).base64EncodedString()
    }
}

/// Where Explorer looks for releases and how it installs them, from its defaults.
public struct UpdateSettings: Equatable, Sendable {
    /// Look for a new release at launch and every few hours.
    public var checksAutomatically = true
    /// Install it without asking, once no Explorer window is open; otherwise ask first.
    public var installsAutomatically = true
    /// A web address of an `update.json` typed in the settings; empty, the build's own: the GitHub
    /// repository's latest release, once `make-app.sh` names it (the GitHub repository the app is built from).
    public var feedAddress = ""

    public init() {}

    /// Nil while neither the settings nor the build say where releases are.
    public func feedURL(builtIn: String? = nil) -> URL? {
        for address in [feedAddress, builtIn ?? ""] {
            if let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
               url.scheme == "https" || url.scheme == "file" {
                return url
            }
        }
        return nil
    }

    /// GitHub serves the latest release's files at a fixed address, so the feed and the archive next to it
    /// are always the newest ones.
    public static func gitHubFeed(repository: String) -> String {
        "https://github.com/\(repository)/releases/latest/download/update.json"
    }

    private enum Key {
        static let checks = "CheckForUpdates", installs = "InstallUpdatesAutomatically", feed = "UpdateFeed"
    }

    public static func load(from defaults: UserDefaults = SuiteDefaults.explorer) -> UpdateSettings {
        var settings = UpdateSettings()
        settings.checksAutomatically = defaults.object(forKey: Key.checks) as? Bool ?? true
        settings.installsAutomatically = defaults.object(forKey: Key.installs) as? Bool ?? true
        settings.feedAddress = defaults.string(forKey: Key.feed) ?? ""
        return settings
    }

    public func save(to defaults: UserDefaults = SuiteDefaults.explorer) {
        defaults.set(checksAutomatically, forKey: Key.checks)
        defaults.set(installsAutomatically, forKey: Key.installs)
        defaults.set(feedAddress, forKey: Key.feed)
    }
}

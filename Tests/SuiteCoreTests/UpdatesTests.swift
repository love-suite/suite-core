import CryptoKit
import Foundation
@testable import SuiteCore
import Testing

@Suite struct UpdatesTests {
    @Test func feedRoundTripsAndComparesBuilds() throws {
        let feed = UpdateFeed(version: "2026.2", build: 120, archive: "Explorer-2026.2.zip", signature: "c2ln",
                              notes: "Faster search", published: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try UpdateFeed.decode(feed.encoded())
        #expect(decoded == feed)
        #expect(feed.isNewer(thanBuild: 119))
        #expect(!feed.isNewer(thanBuild: 120))
    }

    @Test func archiveSitsNextToTheFeedOrOnTheWeb() {
        let feed = URL(fileURLWithPath: "/Users/me/iCloud/Explorer/Updates/update.json")
        var update = UpdateFeed(version: "1", build: 1, archive: "Explorer-1.zip", signature: "")
        #expect(update.archiveURL(relativeTo: feed)?.path == "/Users/me/iCloud/Explorer/Updates/Explorer-1.zip")
        update.archive = "https://example.com/Explorer-1.zip"
        #expect(update.archiveURL(relativeTo: feed)?.absoluteString == "https://example.com/Explorer-1.zip")
        // Nothing outside the release folder, nothing over plain http.
        update.archive = "../../Documents/x.zip"
        #expect(update.archiveURL(relativeTo: feed) == nil)
        update.archive = "http://example.com/x.zip"
        #expect(update.archiveURL(relativeTo: feed) == nil)
    }

    @Test func onlyThePublishersSignaturePasses() throws {
        let key = Curve25519.Signing.PrivateKey()
        let privateKey = key.rawRepresentation.base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let archive = Data("the apps".utf8)
        let signature = try UpdateSignature.sign(archive, privateKey: privateKey)
        try UpdateSignature.verify(archive, signature: signature, publicKey: publicKey)

        #expect(throws: UpdateSignature.Failure.mismatch) {
            try UpdateSignature.verify(Data("changed".utf8), signature: signature, publicKey: publicKey)
        }
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(throws: UpdateSignature.Failure.mismatch) {
            try UpdateSignature.verify(archive, signature: signature, publicKey: other)
        }
        #expect(throws: UpdateSignature.Failure.badKey) {
            try UpdateSignature.verify(archive, signature: signature, publicKey: "nope")
        }
    }

    @Test func settingsDefaultToTheBuildsFeedAndAutomatic() {
        let name = "UpdatesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = UpdateSettings.load(from: defaults)
        #expect(settings.checksAutomatically && settings.installsAutomatically)
        #expect(settings.feedURL() == nil)
        let gitHub = UpdateSettings.gitHubFeed(repository: "me/explorer")
        #expect(settings.feedURL(builtIn: gitHub)?.absoluteString
            == "https://github.com/me/explorer/releases/latest/download/update.json")
        let feed = UpdateFeed(version: "1", build: 2, archive: "Explorer-1-2.zip", signature: "")
        #expect(feed.archiveURL(relativeTo: URL(string: gitHub)!)?.absoluteString
            == "https://github.com/me/explorer/releases/latest/download/Explorer-1-2.zip")
        settings.feedAddress = "https://example.com/update.json"
        settings.installsAutomatically = false
        settings.save(to: defaults)
        let loaded = UpdateSettings.load(from: defaults)
        #expect(loaded == settings)
        #expect(loaded.feedURL(builtIn: gitHub)?.absoluteString == "https://example.com/update.json")
    }
}

@Suite struct SuiteUpdaterTests {
    @Test func aBuildWithoutTheKeyNeverUpdates() {
        // The test runner carries no update key: the updater says so and doesn't check.
        let updater = SuiteUpdater(appName: "Test", defaults: UserDefaults(suiteName: "SuiteUpdaterTests")!, quiet: true)
        #expect(updater.publicKey == nil)
        updater.check(userInitiated: false)
        if case .failed = updater.state {} else { Issue.record("expected a failure without a key, got \(updater.state)") }
        #expect(!updater.describeState().isEmpty)
    }
}

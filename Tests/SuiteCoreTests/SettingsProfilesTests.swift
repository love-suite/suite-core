import Foundation
@testable import SuiteCore
import Testing

@Suite struct SettingsProfilesTests {
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func onlyPreferencesAreKept() {
        let profile = SettingsProfile.capture(name: "Work", from: [
            "local.suite.explorer": ["ShowHiddenFiles": true, "UseTabs": false, "NSWindow Frame X": "0 0 1 1",
                                        "DockSettingsBeforeHiding": Data(), "CurrentProfile": "Old"],
            "local.suite.clipboard": ["historyLimit": 50, "canPaste": true],
            "local.suite.viewer": ["NSWindow Frame PictureViewer": "x"],
        ])
        // Windows' frames come along; the hidden Dock's previous settings and the current profile don't.
        #expect(Set(profile.settings["local.suite.explorer"]!.keys) == ["ShowHiddenFiles", "UseTabs", "NSWindow Frame X"])
        #expect(Set(profile.settings["local.suite.clipboard"]!.keys) == ["historyLimit"])
        #expect(Set(profile.settings["local.suite.viewer"]!.keys) == ["NSWindow Frame PictureViewer"])
    }

    @Test func loadingSetsItsValuesAndResetsTheOthers() {
        let profile = SettingsProfile(name: "Home", settings: ["local.suite.explorer": ["UseTabs": true]])
        let changes = profile.changes(from: ["local.suite.explorer": [
            "UseTabs": false, "ShowHiddenFiles": true, "NSNavLastRootDirectory": "keep",
        ]])
        let explorer = changes["local.suite.explorer"]!
        #expect(explorer.set["UseTabs"] as? Bool == true)
        // Back to its default; the system's own keys are not touched.
        #expect(explorer.remove == ["ShowHiddenFiles"])
    }

    @Test func aPartRestoresFromAProfileOrToItsDefaults() {
        let name = "ProfilesRestore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "ShowToolbarLabels")
        defaults.set(["toolbar": ["rename"]], forKey: "ToolbarLayout")
        defaults.set(true, forKey: "UseTabs")
        let keys = ["ToolbarLayout", "ShowToolbarLabels"]
        // From a profile that only has the layout: the labels go back to their default.
        SettingsProfile.restore(keys, in: defaults, from: ["ToolbarLayout": ["toolbar": ["trash"]]])
        #expect((defaults.dictionary(forKey: "ToolbarLayout")?["toolbar"] as? [String]) == ["trash"])
        #expect(defaults.object(forKey: "ShowToolbarLabels") == nil)
        // To the defaults; what isn't the toolbar's stays.
        SettingsProfile.restore(keys, in: defaults, from: nil)
        #expect(defaults.object(forKey: "ToolbarLayout") == nil)
        #expect(defaults.bool(forKey: "UseTabs"))
    }

    @Test func savedReadMovedAndRemoved() throws {
        let home = try sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = ProfileStore(home: home)
        let profile = SettingsProfile(name: "Work: Mac", settings: ["local.suite.explorer": ["UseTabs": true]])
        let url = try store.save(profile, in: .thisMac)
        #expect(url.lastPathComponent == "Work- Mac.plist")
        #expect(url.path.hasPrefix(home.appendingPathComponent("Library/Application Support/Explorer/Profiles").path))

        var files = store.list()
        #expect(files.map(\.name) == ["Work: Mac"])
        #expect(try store.read(files[0]).settings["local.suite.explorer"]?["UseTabs"] as? Bool == true)

        try store.move(files[0], to: .iCloudDrive)
        files = store.list()
        #expect(files.map(\.location) == [.iCloudDrive])
        #expect(files[0].url.path.contains("com~apple~CloudDocs/Explorer/Profiles"))
    }
}

@Suite struct SettingsMigrationsTests {
    private func fresh() throws -> (UserDefaults, String) {
        let name = "SettingsMigrationsTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func aFreshInstallConvertsNothing() throws {
        let (defaults, name) = try fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        var ran = false
        SettingsMigrations.run([SettingsMigration(version: "27.2") { _ in ran = true }], current: "27.2", defaults: defaults)
        #expect(!ran)
        #expect(defaults.string(forKey: SettingsMigrations.versionKey) == "27.2")
    }

    @Test func anUpdateRunsTheStepsSinceTheLastVersionOnce() throws {
        let (defaults, name) = try fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("27.1", forKey: SettingsMigrations.versionKey)
        var ran: [String] = []
        let steps = ["27.3", "27.1", "27.2", "27.2.1"].map { v in SettingsMigration(version: v) { _ in ran.append(v) } }
        SettingsMigrations.run(steps, current: "27.2.1-dev.4", defaults: defaults)
        #expect(ran == ["27.2", "27.2.1"])
        SettingsMigrations.run(steps, current: "27.2.1", defaults: defaults)
        #expect(ran == ["27.2", "27.2.1"])
        #expect(defaults.string(forKey: SettingsMigrations.versionKey) == "27.2.1")
    }

    @Test func versionsCompareAsReleases() {
        #expect(SuiteVersion("27.1") == SuiteVersion("27.1.0"))
        #expect(SuiteVersion("27.1-dev.9") == SuiteVersion("27.1"))
        #expect(SuiteVersion("27.1") < SuiteVersion("27.1.1"))
        #expect(SuiteVersion("27.9") < SuiteVersion("28.0"))
        #expect(SuiteVersion("27.1.0").release == "27.1")
    }
}

@Suite struct ProfileVersionsTests {
    @Test func aProfileKeepsEachAppsVersionAndPutsItBack() throws {
        let captured = SettingsProfile.capture(name: "Work", from: [
            "local.suite.explorer": ["ShowHiddenFiles": true, SettingsMigrations.versionKey: "27.1"],
            "local.suite.bar": ["BarSettings": Data([1]), SettingsMigrations.versionKey: "27.1.2"],
        ])
        #expect(captured.settings["local.suite.explorer"]?[SettingsMigrations.versionKey] == nil)
        let read = try SettingsProfile.read(captured.data())
        #expect(read.versions == ["local.suite.explorer": "27.1", "local.suite.bar": "27.1.2"])
        let changes = read.changes(from: ["local.suite.explorer": [SettingsMigrations.versionKey: "27.3"]])
        #expect(changes["local.suite.explorer"]?.set[SettingsMigrations.versionKey] as? String == "27.1")
        #expect(changes["local.suite.bar"]?.set[SettingsMigrations.versionKey] as? String == "27.1.2")
    }
}

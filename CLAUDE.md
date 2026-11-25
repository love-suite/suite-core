# Suite Core: project brief

`SuiteCore` is the library every app of the suite depends on. No UI of its own beyond small AppKit helpers,
unit-tested, no app.

## What it holds

- `SuiteDefaults`: where Explorer's settings live (`local.suite.explorer`), read by name from the other
  apps (Suite Settings writes them).
- `ExplorerLink`: the distributed notifications to Explorer, from Suite Settings, Desktop and Bar
  (commands, status keys, opening folders and files, revealing items); `SuiteSettingsApp`: opening Suite
  Settings on a tab. `ClipboardMessage`: those between Clipboard, Explorer and Suite Settings. `BindingsMessage`:
  those between Bindings, Explorer and Suite Settings, with `ExplorerContext` (where the keyboard is in
  Explorer, which Explorer tells Bindings).
- `SettingsMigrations`, `SettingsMigration`, `SuiteVersion`: a change to saved settings between two
  released versions is converted by the update: each app gives its `SuiteUpdater` its steps, each for the
  version that brought the change, run once at the first launch of a new version. Nothing converts
  settings otherwise (no code at launch keeping old names alive). Profiles keep each app's version
  (`SettingsProfile.versions`): loading one puts it back, and the app converts its settings
  (`SuiteUpdater.bringSettingsUpToDate()`, at launch and when told its settings were written).
- `SuiteApps`: what one app knows of another without importing its code: Viewer's, Clipboard's, Bar's,
  Launcher's and Bindings' bundle ids, which files Viewer shows, whether Clipboard and Bindings are turned
  on, starting Launcher (`LauncherMessage`) and Bindings.
- `SettingsProfile`, `ProfileStore`: named settings profiles, on this Mac or in iCloud Drive.
- `Updates.swift`: the update feed (`update.json`), its Ed25519 signature, update settings.
  `SuiteUpdater`: each app keeps itself up to date from its own releases (its feed and the update key's
  public half are in its Info.plist, written by its `make-app.sh`), asking or not, once it isn't in use;
  `quiet` for an agent without windows. `AppRelauncher`: the new copy takes over from the old one.
- `Resources/Localizable.xcstrings`: SuiteCore's strings; each app's `make-app.sh` copies
  `SuiteCore_SuiteCore.bundle` into the app (without it they show in English, never a crash).
- What only the apps handling files need (how folders are sorted and shown, the Trash's folders and
  moving to the Trash, watching folders, Finder's sounds) is in `suite-files`, not here.

## Releasing

No app, so no build script and no update feed: a version is a tag. While a version is being prepared,
`VERSION` stays (27.1): a change an app needs gets a development tag, `v27.1-dev.N` (N the commits since
`VERSION` was set, from 1), which the apps' `.upToNextMinor(from: "27.1.0-dev.1")` picks up at `swift package update`. The
release is `v27.1`, made from `suite` with the other repositories'.

## The suite

This repository is part of Love Suite, one repository per app under `github.com/love-suite`:
`suite-core` (the shared library), `suite-files` (the file layer of the apps handling files),
`suite-guard`, `suite-desktop` (the desktop), `suite-explorer`, `suite-bar` (the Dock), `suite-viewer`,
`suite-clipboard`, `suite-settings` (the settings), `suite-awake` (keeping the Mac awake), `suite-launcher`, `suite-bindings`,
`suite-ai-organizer`; `homebrew-tap` (the tap `love-suite/tap`, one cask per app) and `suite` (the
front page, the suite's version, the scripts that act on every repository). Locally they sit side by side
in `~/GitHub/paul-amour/suite/`.

## Conventions (the same in every repository of the suite)

- The user writes in French and expects answers in French; everything in the code stays in English: code,
  comments, tests, docs, commit messages. Do not add co-author trailers.
- No "…" in menu items, buttons or messages: the user wants none, anywhere.
- Behaviour follows Windows unless Apple's design is asked for.
- Swift Package Manager, `swift-tools-version:5.9`, macOS 13+. Tests use Swift Testing (`import Testing`).
- Toolchain: swiftly, Swift 6.4.2 (`.swift-version`, git-ignored). If `swift test` complains about a
  missing toolchain: `swiftly use 6.4.2`.
- AppKit for windows that need fine control; SwiftUI is allowed for small panels (settings, pickers).
- No private APIs and no system modifications (SIP stays on).
- Git: one worktree per feature under `.worktrees/` (git-ignored), one branch per change
  (`feat/<feature>`, `fix/<area>/<what>`), merged into `main` one by one; `main` stays stable.
- Versions are `AA.Y`, then `AA.Y.Z` for a fix (`VERSION`, tag `vVERSION`: 27.1, then 27.1.1; SwiftPM reads
  `v27.1` as 27.1.0): `AA` is the latest macOS in production (27), `AA.Y` is the same in every repository of
  the suite so the apps work together, `Z` is this repository's own. A change of `AA.Y` is made in `suite`
  and reaches every repository. While a version is being prepared, `VERSION` doesn't move (27.1 now):
  development builds are `VERSION-dev.N`, N the commits since `VERSION` was set, merges aside, from 1 (`make-app.sh`),
  and a change another repository needs gets a development tag, `vVERSION-dev.N`, which releases nothing.
  Dependencies on other repositories of the suite (`suite-core`, `suite-files`, `suite-guard`, settings
  libraries) use
  `.upToNextMinor(from: "27.1.0-dev.1")` (the latest development tag, then the release);
  `Package.resolved` is committed. Tags are never moved once pushed. The build number (`CFBundleVersion`,
  which the updater compares) stays the number of commits.
- Changing two repositories at once: `swift package edit <Package> --path ../<repository>` points at the
  neighbour's working copy until its tag exists, `swift package unedit` goes back. Never committed.
- What two apps need lives in `suite-core` (file code in `suite-files`); an app's own code never goes into another app's repository, and
  an app exposes only its settings, as `<App>Settings`, for Suite Settings.
- Do not run commands that delete user data. Trash instead of delete.
- No code converting saved settings at launch. Before the first release nothing needs converting (the
  developer's own settings don't count): rename freely. Between released versions, a change to saved
  settings is a `SettingsMigration` (suite-core) for the version that brought it, given to the app's
  `SuiteUpdater`, which runs it once after the update.

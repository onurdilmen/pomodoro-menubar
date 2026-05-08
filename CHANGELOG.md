# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-05-08

### Fixed

- **Critical: app crashed on launch on every machine other than the build host.** SwiftPM's auto-generated `Bundle.module` accessor bakes the build-time absolute path into the binary as a fallback (e.g. `/Users/runner/work/...`), and when the resource is not found at the bundle-relative paths it falls back to that hardcoded directory and `fatalError`s. The fix bypasses SwiftPM resources entirely: `package.sh` now copies `index.html` directly into `Pomodoro.app/Contents/Resources/`, and `main.swift` loads it via `Bundle.main`. v0.2.0 is unusable; please install v0.2.1 instead.

## [0.2.0] - 2026-05-08

### Added

- **Auto-update via Sparkle 2.x** — the app now checks for new versions daily and prompts the user when one is available. Powered by [Sparkle](https://sparkle-project.org), the same framework Bartender, Bear, Rectangle, and most indie macOS apps use.
- "Güncellemeleri kontrol et…" / "Check for Updates…" item in the right-click menu (manual check).
- DMG releases are signed with an EdDSA key (`SUPublicEDKey` in Info.plist verifies authenticity before installing).
- `docs/appcast.xml` hosted on GitHub Pages — the app reads this URL on startup to discover new versions.
- `scripts/update_appcast.py` — release workflow uses it to add a new `<item>` to the appcast on every tag push.

### Changed

- `package.sh` now embeds `Sparkle.framework` into `Pomodoro.app/Contents/Frameworks/` and adds the required `@executable_path/../Frameworks` rpath.
- `Info.plist` gained Sparkle settings: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`.
- Bundle size grew from ~176 KB to ~4.1 MB (Sparkle.framework adds ~3 MB; still ~37× smaller than an Electron equivalent).

## [0.1.1] - 2026-05-08

### Added

- Automatic GitHub Actions workflows: `build.yml` (sanity build on every push) and `release.yml` (build DMG and publish GitHub Release on tag push)
- Sequoia (macOS 15) first-launch bypass instructions in README
- `xattr -d com.apple.quarantine` terminal fallback for any macOS version

### Changed

- `package.sh` reads `VERSION` from env (or current git tag) instead of hardcoding `0.1.0`. DMG filename and `CFBundleShortVersionString`/`CFBundleVersion` now reflect the real version.

## [0.1.0] - 2026-05-08

### Added

- Native macOS menu bar Pomodoro timer (~176 KB binary, ~1.5 MB DMG)
- Three modes: Work / Short Break / Long Break with custom durations
- Live countdown in the status bar (`🍅 24:57`)
- Keyboard shortcuts inside the popover (Space, R)
- Global hotkey `⌘⇧P` to toggle the popover from anywhere
- System sound on completion (macOS native `Glass` sound)
- Turkish text-to-speech via `AVSpeechSynthesizer`
- macOS native notification on completion
- Per-feature on/off toggles via right-click menu
- Persistent settings via `UserDefaults`
- Optional auto-start at login via `SMAppService`
- Adopted color emoji 🍅 app icon
- DMG installer with drag-to-Applications layout
- One-command build / install / package script (`./package.sh --all`)

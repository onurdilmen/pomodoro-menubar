# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

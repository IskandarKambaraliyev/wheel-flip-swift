# WheelFlip: instructions for coding agents

WheelFlip is a native macOS menu bar app that reverses the scroll direction of physical mouse wheels and leaves trackpad and Magic Mouse scrolling untouched. The user keeps the system "Natural scrolling" setting on; WheelFlip installs a `CGEventTap` on scroll-wheel events, decides for each event whether it came from a wheel or a touch surface, and negates the deltas of wheel events in place.

[WheelFlip-Spec-for-Claude-Code.md](WheelFlip-Spec-for-Claude-Code.md) is the full specification. This file is the short version of what must stay true, plus what the spec does not tell you. Where the two disagree, this file describes the code as it was built and why.

## Requirements

These hold after any change. Several of them are promises the public landing page makes about the app.

- **Native only.** Swift 5 language mode, SwiftUI, AppKit, CoreGraphics, ServiceManagement. No third-party packages.
- **Fully offline.** No networking code of any kind: no `URLSession`, no Network framework, no update checker, analytics or crash reporting, and no network entitlement. `grep -rE "URLSession|import Network" Sources` must find nothing.
- **Mouse wheel only.** Events with a non-zero scroll phase or momentum phase come from a trackpad or Magic Mouse and pass through completely unmodified.
- **Scroll events only.** The tap's event mask is `scrollWheel` and nothing else. Do not widen it.
- **Menu bar app.** `LSUIElement` is true; there is no Dock icon.
- **Platform.** macOS 14.0 or later, arm64 only.
- **Not sandboxed, Hardened Runtime on.** The entitlements file stays an empty dictionary. An active event tap needs Accessibility permission, which the App Sandbox does not allow.
- **Small and cheap.** The bundle stays under 3 MB (it is about 0.5 MB). The tap callback is O(1): no allocation, no logging, no `String` work, and no lock held longer than a struct copy. No timer runs in steady state.
- **Launch at login** goes through `SMAppService.mainApp` only, and is never switched on automatically.
- **Identity.** App name `WheelFlip`, bundle ID `uz.stiv.wheelflip`, development team `6MD59J7ZW5`. The copyright holder is `Takhirjanovich`; use that name wherever an owner name is needed.
- **Signing.** Apple Development, automatic. Never ad-hoc: the Accessibility grant is tied to the code signature and would be lost on every build.
- **Clean-room.** Do not copy code from UnnaturalScrollWheels (GPL-3.0). Implement from the behaviour described in the spec.
- **Out of scope unless asked:** per-app rules, button remapping, pointer acceleration, smooth-scroll animation, Intel builds, App Store distribution.

## Commands

```bash
make gen               # regenerate WheelFlip.xcodeproj from project.yml (needs xcodegen)
make test              # unit tests
make build             # Release build into build/
make install           # Release build copied to /Applications
make reset-permission  # clear the Accessibility grant for the bundle ID
```

`WheelFlip.xcodeproj` and `build/` are generated and not committed. `Resources/Info.plist` is committed but is rewritten by `make gen` from `project.yml`, so change `project.yml`, not the plist.

## Layout

```
project.yml           XcodeGen project definition: targets, build settings, Info.plist keys
Sources/Engine/       the event tap, and the pure classify + transform functions
Sources/App/          app entry point, app delegate, observable state, login item
Sources/UI/           menu, Settings window and its controller, scroll inspector
Sources/Support/      Accessibility permission helpers, system scroll setting reader
Tests/                unit tests for the pure functions
```

## Engine rules that are easy to break

- **Classification** (`ScrollTransform.isMouseWheel`): a non-continuous event is a wheel. A continuous event is a wheel only when both its scroll phase and momentum phase are zero, and never in Strict mode.
- **Write order.** For each axis, read all three delta fields first, then write line, then fixed-point, then point. Writing the line delta makes CoreGraphics recompute the other two, so they must be written after it. This was measured on macOS 26; any other order silently loses the original values.
- **The tap** sits at `.cghidEventTap`, head-inserted, on its own thread with its own run loop, so a busy main thread cannot get it disabled for timeout. The callback re-enables the tap when the system reports it disabled.
- **Config** reaches the tap thread as a plain value (`EngineConfig`) copied under an `OSAllocatedUnfairLock`. Keep it free of classes and strings.
- Events whose `eventSourceUserData` equals `kWheelFlipMarker` are skipped. Keep that guard even though nothing posts events today.

## Where the code differs from the spec on purpose

Do not change these back to match the spec.

- **The Settings window is owned by AppKit** (`SettingsWindowController`), not a SwiftUI `Settings` scene. The selector the spec uses to open that scene is rejected on macOS 14 and later, and `SettingsLink` needs a live SwiftUI view, which does not exist while the menu bar icon is hidden. The controller also provides ⌘W, which an agent app without window scenes does not get.
- **The menu bar icon is dimmed with a separate template image**, not `.opacity`. SwiftUI passes a `MenuBarExtra` label's image straight to the status item and drops view modifiers. Both states are drawn the same way so the item does not change width when the state changes.
- **Release builds strip in place** (`DEPLOYMENT_POSTPROCESSING`), because the spec's strip settings do nothing in a plain `xcodebuild build`. The Makefile therefore deletes the Release product before building: without that, a rebuild that only re-signs the app regenerates the dSYM from the already stripped binary and leaves it empty.
- **Release builds do not get `get-task-allow`** (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`). A debuggable app would let any local process borrow its Accessibility grant.
- **The app stays inert under XCTest** (`AppDelegate.isRunningTests`). The unit tests are hosted in the app, and it must not prompt for permission or install a tap while hosting them.
- **Permission polling** runs once a second only while the tap is not running, and a stale-permission error is reported only after three failed starts in a row, because trust can be reported a moment before the tap can be created.
- **The Settings window opens at 420 × 360** as the spec says, but the form is about 836 points tall, so it scrolls, is resizable in height, and scrolls itself to the Status section when permission is missing.

## Verifying a change

- `make test` passes and the build has no warnings.
- **Engine changes need a test against a real tap**, not only the unit tests. A binary started directly from a terminal inherits that terminal app's Accessibility permission, so it can run with a live tap; `open -a WheelFlip` gives the app its own identity and its own permission prompt. To test without scrolling anything on screen, post synthetic scroll events tagged through `eventSourceUserData` at `.cghidEventTap`, read them back in a second tap at `.cgSessionEventTap`, and drop them there. Cover wheel, smooth wheel, phased and momentum events, both axes, linear mode, Strict mode and the disabled state.
- **UI changes need a real run.** A build cannot show whether the Settings window opens, whether the menu bar icon dims, or what the menu contains.
- Check the Release bundle after build-setting changes: size, `arm64` only, a valid signature, the hardened runtime flag, and no `get-task-allow`.

## Releasing

1. Set the version in `project.yml` (`CFBundleShortVersionString` and `CFBundleVersion`).
2. `make build`, then zip with `ditto -c -k --keepParent build/Build/Products/Release/WheelFlip.app WheelFlip.zip`. `ditto` keeps the code signature intact.
3. Publish a GitHub release with that file attached. The asset must be named exactly `WheelFlip.zip`, and the release must not be a draft or pre-release: the landing page's download button points at `releases/latest/download/WheelFlip.zip`.
4. Update `version` in `src/site.ts` of the landing page repository (`IskandarKambaraliyev/wheel-flip-landing-react`) and release it.

The app is signed with an Apple Development certificate and is not notarized, so people who download it confirm the first launch in System Settings. The landing page at <https://wheel-flip.stiv.uz> documents that.

The landing page also states facts about the app: its features, that it is offline, that it receives scroll events only, its size, and the installation steps. When a change here makes one of those statements untrue, the landing page has to change with it.

## Working agreements

- Commit or push only when asked. The repository has a single `main` branch.
- Never rewrite pushed history or force-push unless explicitly asked.
- Keep [README.md](README.md) in step with behaviour that users can see.
- Comments say why, not what. Match the density and tone of the surrounding code.

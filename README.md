# WheelFlip

A tiny native macOS menu bar app that reverses the scroll direction of **mouse wheels only**. Trackpad and Magic Mouse scrolling are left exactly as they are.

## Why

macOS has a single "Natural scrolling" setting shared by the mouse and the trackpad. Most people want natural scrolling on the trackpad and traditional scrolling on a wheel mouse, and the system cannot do both.

WheelFlip watches scroll events with an event tap, works out whether each one came from a wheel or from a touch surface, and flips only the wheel ones. It is fully offline: there is no networking code, no update checker and no analytics.

## Requirements

- macOS 14 or later, Apple Silicon
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build (`brew install xcodegen`)

## Install

```bash
make install        # Release build → /Applications/WheelFlip.app
open -a WheelFlip
```

Quit a running copy (menu bar icon → Quit WheelFlip) before installing over it.

The project is signed with the team set in `project.yml` (`DEVELOPMENT_TEAM`). Change it there to build under a different Apple developer account. Do not switch to ad-hoc signing: the Accessibility permission is tied to the code signature and would be lost on every build.

Other targets: `make gen` regenerates the Xcode project, `make test` runs the unit tests, `make build` builds without installing.

## Granting Accessibility access

WheelFlip changes scroll events as they pass through the system, which macOS only allows for apps with Accessibility access.

1. On first launch macOS asks for the permission and WheelFlip opens its Settings window.
2. Open **System Settings → Privacy & Security → Accessibility** and switch **WheelFlip** on.
3. WheelFlip notices within a second and starts working. No relaunch is needed.

## Recommended setup

- **System Settings → Trackpad / Mouse → Natural scrolling: on.** This is what the trackpad uses.
- **WheelFlip → Invert vertical: on** (the default). The wheel then scrolls the traditional way.

Optional settings:

- **Invert horizontal** reverses tilt wheels and Shift+wheel.
- **Linear scrolling** removes wheel acceleration, so every notch scrolls the same number of lines.
- **Show menu bar icon** can be turned off. WheelFlip keeps running; open the app again (Finder, Spotlight or `open -a WheelFlip`) to get the Settings window back.

## Troubleshooting

**The wheel is not reversed.** Check Settings → Status. Accessibility must say *Granted* and the menu bar icon must not be dimmed.

**Accessibility is granted but nothing happens.** This can happen after the app was rebuilt with a different signature. Run `make reset-permission`, relaunch WheelFlip and grant access again. Removing WheelFlip from the Accessibility list and adding it back does the same.

**The wheel is reversed twice, or not at all.** A vendor driver such as Logi Options+ may already be reversing it. Turn the inversion off in one of the two apps.

**A device is treated wrongly.** Open Settings → Scroll inspector and scroll with that device. It shows the raw event fields and whether WheelFlip treated the event as a mouse wheel. If a touch device is being reversed by mistake, set Detection to **Strict**, which only reverses classic notched wheels. Smooth-scrolling mice are then left alone as well.

**Magic Mouse.** It reports touch-style events, so it follows the system setting like a trackpad. That is intentional.

## Notes

WheelFlip is a clean-room implementation written from a behavioural description. It was inspired by [UnnaturalScrollWheels](https://github.com/ther0n/UnnaturalScrollWheels) but contains none of its code.

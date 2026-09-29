# How DisplayToggle works

## The one call that matters

macOS has no public API to disconnect a display. The window server does have a private
one, `SLSConfigureDisplayEnabled(config, displayID, enabled)` in the SkyLight framework
(also exported as `CGSConfigureDisplayEnabled` from CoreGraphics). It runs inside an
ordinary `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` transaction,
exactly like changing a resolution. BetterDisplay's "Disconnect" and the older
DisableMonitor use the same call.

DisplayToggle looks the symbol up with `dlsym` at runtime. If a future macOS removes it,
you get an error message instead of a crash.

The transaction is completed with `.forSession`, so a disconnect never outlives your
login session. Reboot, log out or replug the cable, and the monitor is back. That's the
safety net: you can't configure yourself into a Mac with no screen that stays that way.

## Remembering what was turned off

A disconnected display drops out of `CGGetOnlineDisplayList`, so there'd be no way to
find its ID again. DisplayToggle writes each display it turns off to
`~/Library/Application Support/DisplayToggle/disconnected.json` (ID, name, vendor,
model, serial, resolution) and removes it once it's back. Any entry whose ID shows up
online again (after a replug or reboot) is dropped automatically. The menu bar app and
`displayctl` share this file, so a change made in one shows up in the other.

## Physical vs. virtual displays

On Apple Silicon, every real panel has an `IOMobileFramebufferShim` entry in the
IORegistry with its EDID identity under `DisplayAttributes › ProductAttributes`.
DisplayToggle treats a display as physical when its CoreGraphics vendor/model/serial
match one of those entries (or it's the built-in panel). Virtual screens, such as the
ones remote-desktop tools and display dummies create, have no entry.

## Safety rules

- Never disconnect the last active display.
- If only virtual displays would remain, warn first (a confirmation dialog in the menu,
  a message on stderr in the CLI). When the remote session ends, that virtual screen
  disappears and the Mac is headless until you reconnect remotely or restart it
  (for example `sudo shutdown -r now` over SSH).
- The state file is only written after macOS accepted the change.

## Code map

| File | What it does |
|---|---|
| `Sources/DisplayCore/DisplayInfo.swift` | Display model, safety verdicts, errors |
| `Sources/DisplayCore/DisplayLogic.swift` | Pure logic: safety rule, ID/name lookup, state merge (unit tested) |
| `Sources/DisplayCore/StateStore.swift` | The JSON state file (unit tested) |
| `Sources/DisplayCore/DisplayManager.swift` | CoreGraphics, IOKit and SkyLight calls |
| `Sources/DisplayToggle/CLI.swift` | `displayctl` |
| `Sources/DisplayToggle/MenuBar.swift` | The menu bar app |
| `Sources/DisplayToggle/main.swift` | Picks CLI or menu bar mode |

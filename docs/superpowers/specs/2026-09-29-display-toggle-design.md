# DisplayToggle — design

A tiny BetterDisplay-style tool for macOS (Apple Silicon, macOS 27) that disconnects
monitors in software so they disappear from System Settings › Displays, and
reconnects them later.

## Decisions

- **Form factor:** one Swift binary, two faces.
  - Launched as `DisplayToggle.app` → menu bar icon, no Dock icon.
  - Run as `displayctl <command>` (symlink to the same binary) → CLI.
- **Persistence:** a disconnect lasts until reboot, logout, or cable replug; then the
  monitor comes back on its own. Nothing re-disconnects at login. This is the
  escape hatch against ending up with no visible screen.
- **Mechanism:** private SkyLight call `SLSConfigureDisplayEnabled(config, id, bool)`
  inside a normal `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration`
  transaction (the same thing BetterDisplay's "Disconnect" and DisableMonitor use).
  Resolved at runtime with `dlsym` (falls back to `CGSConfigureDisplayEnabled`), so a
  missing symbol is a clean error, not a crash or link failure.

Rejected: mirroring (public API, but the display still shows in Settings and stays
lit) and DDC power-off (the panel sleeps but macOS still treats it as connected).

## Components

| File | Responsibility |
|---|---|
| `Sources/Displays.swift` | Core: enumerate displays, disconnect/reconnect, safety check, remembered-state file. No UI. |
| `Sources/CLI.swift` | Argument parsing and table output for `displayctl`. |
| `Sources/MenuBar.swift` | `NSStatusItem` menu, rebuilt every time it opens. |
| `Sources/main.swift` | Arguments present → CLI; otherwise → menu bar app. |
| `build.sh` | `swiftc` → `build/DisplayToggle.app` (Info.plist with `LSUIElement`), ad-hoc codesign. |
| `install.sh` | Copy app to `~/Applications`, symlink `displayctl` onto `PATH`. |

## Data flow

1. **List:** `CGGetOnlineDisplayList` gives the connected displays (ID, vendor/model/serial,
   bounds, main). Names come from `NSScreen.localizedName`. Displays in the remembered-
   state file that are *not* online are shown as **off**.
2. **Off:** safety check → config transaction with `enabled = false` → on success, append
   `{id, name, vendor, model, serial}` to
   `~/Library/Application Support/DisplayToggle/disconnected.json`.
3. **On:** config transaction with `enabled = true` → remove the entry from the file.
4. **Pruning:** any remembered ID that shows up online again (after a replug or reboot) is
   dropped from the file automatically.

The CLI and the menu bar app share only that JSON file. The menu re-reads it every time
it opens, so a change made in one shows up in the other.

## CLI

```
displayctl list                  # ID, name, on/off, main, resolution
displayctl off <id|name>         # name = case-insensitive substring, must be unique
displayctl on  <id|name>
displayctl on  --all             # reconnect everything this tool disconnected
```

Exits non-zero with a message on any failure.

## Menu

- One item per display: a checkmark means on. Click to toggle. Shows name and resolution.
- "Turn all back on" (only when something is off)
- "Launch at login" toggle (`SMAppService.mainApp`)
- Quit

## Safety and error handling

- Refuse to disconnect a display if no other active display would remain.
- If the only display that would remain is the virtual **Remote** display, show a
  warning: that display vanishes when the remote session ends, which leaves the Mac
  headless until you reconnect remotely or over SSH (`displayctl on --all`).
- Any `CGError` from the transaction is reported. The config is cancelled on failure,
  and the state file is only updated after success.

## Testing

- The pure logic (safety rule, name/ID resolution, state pruning) runs through
  `displayctl selftest`, with no hardware side effects.
- `displayctl list` against the real hardware (read-only).
- Live off → on round-trip on one physical monitor, run **only with your go-ahead**,
  because it blanks that monitor and moves its windows.

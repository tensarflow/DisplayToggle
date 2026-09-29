# DisplayToggle

Turn monitors off in software so they disappear from System Settings › Displays,
and turn them back on later. The same trick as BetterDisplay's "Disconnect".

## Install

```bash
./install.sh
```

Puts `DisplayToggle.app` in `~/Applications`, links `displayctl` into `~/.local/bin`,
and starts the menu bar icon.

## Use

Menu bar: click the display icon; a checkmark means the monitor is on. Click to toggle.

Terminal (also works over SSH):

```bash
displayctl list
displayctl off VG27A      # or the ID from `list`
displayctl on VG27A
displayctl on --all
```

## Good to know

- A monitor turned off here comes back by itself after a reboot, logout, or cable replug.
- It refuses to turn off the last active display, and warns when only a virtual
  (remote-desktop) display would remain.
- Uses the private SkyLight call `SLSConfigureDisplayEnabled`; a future macOS may remove it,
  in which case the tool reports an error instead of doing anything.
- Remembered state: `~/Library/Application Support/DisplayToggle/disconnected.json`.

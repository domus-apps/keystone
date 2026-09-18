<p align="center">
  <img src="Assets/banner.png" alt="Keystone: Input switching, without the delay" />
</p>

<p align="center">
  Instant input-source switching for macOS, Caps Lock, rerouted to a spare key at the HID layer.<br />
  A single Swift Package, builds with the <code>swift</code> CLI alone, no Xcode project required.
</p>

## What it does

macOS can switch input sources with Caps Lock, but that path carries a deliberate delay
(it has to distinguish a tap from engaging Caps Lock). The classic fix is to remap
Caps Lock to a spare function key and bind "Select next source in Input menu" to it,
usually via Karabiner-Elements, which runs a virtual keyboard driver and daemons for the
privilege.

Keystone does the remap the way `hidutil` does: it books a `UserKeyMapping` entry into
macOS's own HID event system, where the **kernel** rewrites Caps Lock → F19. No virtual
driver, no event tap, no Accessibility or Input Monitoring permission, no process of
Keystone's ever sees a keystroke. The app itself just sits in the menu bar and
re-asserts the mapping when the system would forget it (wake from sleep, a keyboard
reconnecting).

The ⌘ and ⌥ keys, either side, can switch too. Each key has its own action (next input
source, or one specific source) and its own trigger: switch on a lone release, keeping
the key a modifier so every shortcut still works, or switch the instant it goes down,
giving up its modifier role. The instant kind is rerouted in the kernel like Caps Lock,
but to *nothing*: no function key exists, so no other app or system shortcut can ever
see the press. Keystone watches the physical key below the remap, at the HID device
layer, and switches through the Text Input Source API. That needs the Input Monitoring
permission and stops during secure input (password fields, Terminal's Secure Keyboard
Entry). Caps Lock can take that path as well, when a specific source is wanted; the
system shortcut path is kept for one key at a time because that is where its
permission-free, secure-input-proof behavior comes from, and it is the only path with
a function key.

## Setup

1. If Karabiner-Elements was doing this job, uninstall it first (its settings window →
   Uninstall), quitting is not enough, its daemons keep remapping.
2. Launch Keystone and follow the onboarding.
3. In System Settings › Keyboard › Keyboard Shortcuts… › Input Sources, record
   "Select next source in Input menu" by pressing Caps Lock (it already types F19).

## Settings

- **General**: launch at login, hide the menu bar icon, updates.
- **Remapping**: the master switch, then one section per key (Caps Lock, left/right ⌘,
  left/right ⌥): action (off, system shortcut, next input source, or a specific
  source), how a modifier switches (on release keeping shortcuts, or instantly on
  press), the function key for the system-shortcut key (F13–F20), and
  hold-for-real-Caps-Lock.

## Development

```sh
swift run                # menu bar app, dev build
./Scripts/dev.sh         # rebuild-and-relaunch loop
./Scripts/test.sh        # unit tests
./Scripts/bundle.sh      # standalone build/Keystone.app
swift run Keystone --language ko --settings   # force a localization (dev builds have no bundle ID)
```

## Notes

- The remaps are active exactly while Keystone runs: quitting (or toggling it off)
  clears the mapping and hands every key back to stock macOS. Launch at login keeps
  it seamless across restarts.
- A force-quit or crash can't clean up after itself; the next launch, toggle, or
  reboot sweeps the mapping away.

## License

MIT, see [LICENSE](LICENSE). Bundled third-party software and its licenses are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

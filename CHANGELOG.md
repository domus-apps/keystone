# Changelog

All notable changes to Keystone are documented here. The release workflow publishes each version's section as the GitHub release notes and embeds it in the Sparkle appcast, so the in-app update dialog shows the same notes. A release fails early if its version has no section here.

Keep each bullet on a single line: release notes render line breaks literally (both on GitHub and in the update dialog), so wrapped lines would break mid-sentence.

## 1.0.4

### Changed

- Raised the icon's arch: the keystone's narrow protrusion doesn't read as the glyph's top edge, so the ring itself is now what sits optically centered.

## 1.0.3

### Changed

- New brand color: terracotta — the fired brick of the Roman arches that gave the keystone its job — replacing the amber that sat too close to its sibling Transom.
- The icon's arch is now optically centered, its voussoir seams cut the flanks into equal stones, and impost seams mark where the arc meets the legs.

## 1.0.2

### Changed

- Quitting Keystone now clears the mapping and returns Caps Lock to stock macOS behavior — the remap is active exactly while the app runs, so what you see in the menu bar is the whole story. Launch at login keeps switching seamless across restarts. (A force-quit can't clean up after itself; the next launch, toggle, or reboot does.)

## 1.0.1

### Fixed

- The Caps Lock mapping was installed on every HID service in the system, including the Apple vendor services that translate the keyboard's fn row into brightness/volume events — which silently broke those keys (and apps driven by them, such as Transom) until the mapping was cleared, even after quitting Keystone. The mapping is now scoped to actual keyboard services, and enabling, disabling, or re-asserting the remap first sweeps away the stray mappings older versions left behind.

## 1.0.0

- Initial release: Caps Lock rerouted to a spare function key (F19 by default, F13–F20 selectable) inside macOS's HID system — instant input-source switching with none of Caps Lock's built-in delay, and no process ever touching a keystroke.
- The mapping is re-asserted automatically after sleep and whenever a keyboard (re)connects, so Bluetooth keyboards can't shake it off.
- First-run onboarding walks through the one manual step: binding "Select next source in Input menu" to the rerouted key in System Settings.
- Menu bar toggle, Settings with launch at login and destination-key choice, and Sparkle auto-updates.

# Changelog

All notable changes to Keystone are documented here. The release workflow publishes each version's section as the GitHub release notes and embeds it in the Sparkle appcast, so the in-app update dialog shows the same notes. A release fails early if its version has no section here.

Keep each bullet on a single line: release notes render line breaks literally (both on GitHub and in the update dialog), so wrapped lines would break mid-sentence.

## 1.0.1

### Fixed

- The Caps Lock mapping was installed on every HID service in the system, including the Apple vendor services that translate the keyboard's fn row into brightness/volume events — which silently broke those keys (and apps driven by them, such as Transom) until the mapping was cleared, even after quitting Keystone. The mapping is now scoped to actual keyboard services, and enabling, disabling, or re-asserting the remap first sweeps away the stray mappings older versions left behind.

## 1.0.0

- Initial release: Caps Lock rerouted to a spare function key (F19 by default, F13–F20 selectable) inside macOS's HID system — instant input-source switching with none of Caps Lock's built-in delay, and no process ever touching a keystroke.
- The mapping is re-asserted automatically after sleep and whenever a keyboard (re)connects, so Bluetooth keyboards can't shake it off.
- First-run onboarding walks through the one manual step: binding "Select next source in Input menu" to the rerouted key in System Settings.
- Menu bar toggle, Settings with launch at login and destination-key choice, and Sparkle auto-updates.

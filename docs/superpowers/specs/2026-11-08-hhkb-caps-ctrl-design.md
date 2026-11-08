# Design: HHKB Caps↔Ctrl Preset (Toshy fork)

Author's workflow: 10+ years macOS/HHKB habits — full Caps↔Left Ctrl swap, IME on Ctrl+Space, macOS-style Cmd shortcuts via cmd position keys.

## Decisions (made 2026-11-08)

- Distribution shape: **idempotent preset script** (Option A) in fork `lovelock/Toshy`; upstream `main` stays synced; preset branch holds only additions.
- What the preset mutates on a target machine (exactly three things + one opt-in):
  1. `~/.config/toshy/toshy_config.py`: two marker-wrapped insertions (below).
  2. Toshy prefs: `capslock_mode = caps_is_caps` (so the caps-mode machinery never claims CAPSLOCK and cannot fight the swap modmap).
  3. (opt-in, only if `~/.config/fcitx5/config` exists) `Hotkey/TriggerKeys` first entry → `Control+space`. On ibus/GNOME machines this is already the standard toggle; nothing else needed.
- DE-agnostic: both insertions are guarded by kbtype (Apple/Windows) + focus/remote, no DESKTOP_ENV condition. SPOTL exists on all supported DEs, so the passthrough keymap is needed everywhere (KDE: layout-switch steal; GNOME: Super-Space steal — passthrough beats both).
- The modmap must register BEFORE `[Global GUI conditional modmaps]` maps (first-match-wins on `Key.LEFT_CTRL`), the keymap BEFORE the `setup_spotlight_input_keymaps(` try-block (SPOTL intercepts `LC-Space`).
- On Toshy upgrades the SCAN/slice regions may be regenerated → rerun the script (documented in README).
- Not doing: upstream PR; machine-image of other prefs; omarchy note — when running omarchy-style Hyprland tooling you don't need Toshy at all.

## Applied blocks (verbatim payload of the preset)

Block 1 — modmap (inserted immediately before the ACTIVE line `# [Global GUI conditional modmaps] Change modifier keys as in xmodmap`):

```python
# [User custom modmap - preset hhkb-caps-ctrl] Caps <-> Left Ctrl FULL literal swap
# (Mac/Win kbtype). Physical Caps = literal Left Ctrl in every app (GUI + terminals);
# physical Left Ctrl key = CapsLock toggle. Requires capslock_mode='caps_is_caps'.
# Registered BEFORE the base GUI/Terms "Win kbd" modmaps: apply_modmap is
# first-match-wins per inkey (see xwaykeyz transform.py).
modmap("Cond modmap - User - Caps<->LCtrl full swap - Mac/Win kbd", {
    Key.CAPSLOCK:               Key.LEFT_CTRL,                  # Caps is literal Left Ctrl everywhere
    Key.LEFT_CTRL:              Key.CAPSLOCK,                   # Left Ctrl is CapsLock
}, when = lambda ctx:
    cnfg.screen_has_focus and
    (ctx_kbd_is_apple or ctx_kbd_is_windows) and
    not ctx_app_is_remote
)
```

Block 2 — keymap (inserted immediately before the `try:` line that guards `setup_spotlight_input_keymaps(`):

```python
# [User keymap - preset hhkb-caps-ctrl] Free physical Ctrl+Space (Caps + Space)
# for the fcitx5/ibus IME trigger. The SPOTL module below (setup_spotlight_input_keymaps)
# intercepts LC-Space and remaps it to the DE's layout-switching combo (e.g.
# Meta+Alt+L on KDE) in every context, so the Space never reaches apps or the
# input method. This keymap re-emits the combo unchanged -- a true passthrough
# (a None value here would BLOCK the key instead). Registered before the SPOTL
# setup so it wins the first-match-wins race. Cmd+Space (RC-Space -> launcher,
# e.g. KRunner) is intentionally untouched; that mapping lives in SPOTL.
keymap("User: Ctrl+Space for IME (fcitx5) passthrough", {
    C("LC-Space"):          C("C-Space"),           # real Ctrl+Space through to app/IME
    C("Shift-LC-Space"):    C("Shift-C-Space"),     # real Ctrl+Shift+Space through
}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote
)
```

Both blocks are wrapped in the repo copy between the marker lines
`###  PRESET: hhkb-caps-ctrl (modmap)  ###` / `(keymap)  ###` start/end forms for idempotency detection.

## Verification state on the owner's machine (2026-11-07)

evtest on the Toshy virtual keyboard proved: physical Caps+Space previously emitted `Alt+Meta+L` (SPOTL steal) and no Space; after the two insertions the Space reaches apps/IME. fcitx5 verbose boot log prints `Trigger Key: Control+space`. Shift+Space was the control case that always worked.

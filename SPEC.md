# Accent Hold — functional specification

Accent Hold brings the macOS "press and hold" accent menu to Omarchy.

## Reference: the macOS behavior

Sources: Apple's Mac User Guide ("Enter characters with accent marks on Mac",
`mh27474`), the `ApplePressAndHoldEnabled` defaults key, and the
`PressAndHold.app` keyboard plists (`Roman-Accent-<letter>` entries).

- Holding a letter key that has accented variants opens a small popover
  above the text insertion point.
- The popover shows each variant with a number underneath it.
- A variant is chosen by typing its number, by clicking it, or by moving with
  the arrow keys and confirming with Return or Space.
- The letter typed when the key went down is replaced by the chosen variant.
- Escape closes the popover and keeps the original letter.
- Typing any other character closes the popover, keeps the original letter
  and inserts the typed character.
- Letters without variants never show a popover.
- While press and hold is enabled, held letters do not auto-repeat.
- The popover opens after the system key-repeat delay; it takes the place
  of auto-repeat.
- Shift (or Caps Lock) shows the uppercase variants.

The English (ABC / US) variant sets, in macOS order:

| Key | Variants          |
|-----|-------------------|
| a   | à á â ä æ ã å ā   |
| c   | ç ć č             |
| e   | è é ê ë ē ė ę     |
| i   | î ï í ī į ì       |
| l   | ł                 |
| n   | ñ ń               |
| o   | ô ö ò ó œ ø ō õ   |
| s   | ß ś š             |
| u   | û ü ù ú ū         |
| y   | ÿ                 |
| z   | ž ź ż             |

## Accent Hold behavior

### Trigger

1. **F1** — Holding a letter that has variants, with no modifier or with
   Shift only, opens the accent popup.
2. **F2** — The popup opens after the hold delay. The default hold delay is
   Hyprland's `input.repeat_delay` minus a 60 ms lead, so the popup always
   opens before the application starts to auto-repeat the letter. The
   minimum is 120 ms. `holdDelay` in the config file overrides the default.
3. **F3** — The letter is typed normally when the key goes down. Nothing is
   delayed while typing.
4. **F4** — Pressing any other key before the delay ends cancels the
   popup. Releasing the letter before the delay ends cancels the popup.
5. **F5** — A letter held with Ctrl, Alt, Super or AltGr never opens the
   popup. Hyprland shortcuts such as `SUPER + E` keep working.
6. **F6** — Letters without variants keep their normal behavior, including
   auto-repeat.
7. **F7** — The popup never opens for windows whose class matches an entry in
   `excludeClasses`, and never opens while an application inhibits shortcuts
   (games, virtual machines, remote desktops).

### Popup

8. **F8** — The popup shows the variants on one row, in the configured
   order, with the numbers 1 to 9 (then 0 for a tenth variant) under them.
9. **F9** — The popup uses the colors and fonts of the current Omarchy theme.
10. **F10** — Wayland gives third-party programs no access to the text caret
    position. The popup is centered on the focused window. With
    `"position": "pointer"`, it opens above the mouse pointer instead.
11. **F11** — Shift held at the start of the hold, or Caps Lock on, shows the
    uppercase variants.

### Choosing

12. **F12** — A number key selects that variant: the popup closes and the
    original letter is replaced.
13. **F13** — A click on a variant does the same.
14. **F14** — Left/Right (and Tab/Shift+Tab) move the highlight. The first
    move highlights the first (or last) variant.
15. **F15** — Return or Space confirm the highlighted variant. With nothing
    highlighted, they close the popup and are typed into the application.
16. **F16** — Escape, or a click outside the popup, closes it and keeps the
    original letter.
17. **F17** — Any other key closes the popup, keeps the original letter and
    is typed into the application. Backspace therefore deletes the original
    letter, as on macOS.
18. **F18** — The replacement is a Backspace followed by the variant, typed
    with `wtype`. It works in every Wayland and XWayland application.

### Lifecycle and safety

19. **F19** — Enabling the plugin activates the feature at once. Disabling or
    removing it removes every Hyprland bind it added.
20. **F20** — The feature survives Hyprland config reloads.
21. **F21** — The plugin never edits user configuration files, never needs
    root, never joins the `input` group and never reads `/dev/input`. It only
    sees the keys that Hyprland's keybind engine already sees.

## Configuration

Optional file: `~/.config/omarchy/accent-hold.json`. It is read at start and
reloaded on save.

```json
{
  "holdDelay": 0,
  "position": "window",
  "excludeClasses": ["^steam_app_"],
  "accents": { "e": "éèêëēėę" }
}
```

- `holdDelay`: milliseconds, `0` means automatic (F2).
- `position`: `"window"` or `"pointer"`.
- `excludeClasses`: Lua patterns matched against the window class.
- `accents`: per-letter variant strings that replace the defaults; an empty
  string turns a letter off. Uppercase variants are derived automatically.

## Out of scope

- Anchoring the popup at the text caret (not exposed on Wayland).
- Non-Latin layouts and dead-key layouts.
- Per-application ordering of variants.

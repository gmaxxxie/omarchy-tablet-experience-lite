# Omarchy Tablet Lite

**The tablet experience, reduced to two things: an on-screen keyboard and voice
input.** A lite sibling of
[omarchy-tablet-experience](https://github.com/gmaxxxie/omarchy-tablet-experience),
for a 2-in-1 where the rest (rotation, mode switching, handwriting, window
management, bar decluttering) is noise.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

## What it does

- **Virtual keyboard** — `wvkbd-deskintl`, a wlroots-native keyboard with
  **Ctrl / Super / Alt / Shift / AltGr**, **F1–F12**, a **number row** (Chinese
  candidate selection) and **arrows**. Built for the tablet with a visible
  **▼ collapse key** so it can be folded away anywhere. Toggle with `SUPER+U`,
  the bar **⌨** button, or
  `omarchy-shell maxt.tablet-lite keyboardToggle`. `squeekboard` is the
  fallback when the lite build is absent.
- **Voice input** — the bar **🎤** button opens a bottom hold-to-talk overlay.
  Press & hold → `voxtype record start`, release → local transcription typed at
  the cursor with `wtype` (CJK works in terminals and every toolkit). **Delete /
  Clear / Enter** fix or submit the line; a left-side **caret pad** moves through
  it; the expandable **CLI keys** grid sends `esc` `/` `tab` `⇧tab` `⌃C` `⌃D`
  `⌃J` `⌃T` for pi / codex CLI on a touch-only screen.
- Voice and keyboard are **mutually exclusive**: opening one closes the other.
- **CLI keys + caret pad also ride with the keyboard**, parked just above the
  real wvkbd surface, so `esc` / `⌃C` stay reachable while typing by hand.

Deliberately absent: laptop/tablet state machine, rotation, auto-orientation,
keyboard-auto-switch, handwriting, window management, bar decluttering,
multi-touch gestures, lock/login-screen integration.

## Requirements

- Omarchy 4.x (Quickshell shell) + Hyprland 0.56+ (Lua config API), Arch-based.
- `wtype` and **voxtype** (AUR: `voxtype-bin`) for voice input.
- `squeekboard` (fallback keyboard) and build deps for the wvkbd build
  (`cairo pango wayland libxkbcommon`; already present on most Omarchy
  installs).
- A touchscreen helps, but nothing is hardware-specific: the keyboard and voice
  work with a mouse too.

## Install

```sh
# 1. the plugin (QML service + bar widget):
omarchy plugin add https://github.com/gmaxxxie/omarchy-tablet-experience-lite.git --enable

# 2. system side (helper scripts, wvkbd build, Hyprland hook, voxtype wiring):
~/.config/omarchy/plugins/maxt.tablet-lite/install.sh
```

The repository root is the plugin folder, so after step 1 the clone lives at
`~/.config/omarchy/plugins/maxt.tablet-lite` and `install.sh` runs from there.
It also works from a dev clone.

`install.sh` options:

| Flag | Effect |
|---|---|
| *(none)* | helpers + wvkbd build + `SUPER+U` hook + voxtype wiring |
| `--no-packages` | never invoke pacman |
| `--no-wvkbd` | skip the build, use the squeekboard fallback |
| `--dry-run` | preview everything, change nothing |
| `--verify` | post-install self-check (read-only) |

Nothing outside `$HOME` is written, and no sudo is needed when `squeekboard`
and `wtype` are already installed. Every modified file gets a
`*.bak.<timestamp>` first.

**Reload the shell once** (or re-login) so the plugin loads fresh, then
`install.sh --verify`.

## Usage

| Action | Input |
|---|---|
| Toggle virtual keyboard | `SUPER+U` · bar **⌨** · `omarchy-shell maxt.tablet-lite keyboardToggle` |
| Fold the keyboard away | its **▼** key |
| Open/close voice input | bar **🎤** · `omarchy-shell maxt.tablet-lite voiceInputToggle` |
| Dictate | press & hold the big mic, release to transcribe |
| Fix the text | **Delete** (BackSpace) / **Clear** (select-all+delete; readline `Ctrl+A`+`Ctrl+K` in terminals) / **Enter** |
| Move the caret | the left-side **← → ↑ ↓** pad |
| Agent keys (pi / codex) | **CLI keys ▲** → `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T` |

IPC: `getState` · `voiceInputToggle|Show|Hide` · `keyboardToggle|Show|Hide` ·
`cliKeysToggle` · `clearNow` (`omarchy-shell maxt.tablet-lite <method>`).

## Files

```
Service.qml             QML service: voice overlay, caret/CLI pad, VK state
BarWidget.qml           bar buttons: ⌨ keyboard + 🎤 voice
scripts/texp-vk         keyboard toggle/show/hide (wvkbd or squeekboard)
scripts/texp-install-wvkbd  user-local wvkbd-deskintl build (pinned + SHA-256)
scripts/texp-vtext      voxtype post-processing (technical-term table)
scripts/texp-voxtype-wire   voxtype pre_output hook (mousehop release)
scripts/texp-mousehop   hand a software-KVM input capture back before typing
config/hypr/tablet-lite.lua  SUPER+U + above_lock rule
config/wvkbd/wvkbd-hide-key.patch  ▼ collapse key
config/voxtype/replacements.tsv    default replacement table
```

## Uninstall

```sh
~/.config/omarchy/plugins/maxt.tablet-lite/uninstall.sh
omarchy plugin remove maxt.tablet-lite
```

## License

MIT — see [LICENSE](LICENSE). Derived from omarchy-tablet-experience by the
same author.

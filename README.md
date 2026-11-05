# Omarchy Tablet Lite

**The tablet experience, reduced to what a touch screen actually needs: an
on-screen keyboard, voice input, and screen rotation.** A lite sibling of
[omarchy-tablet-experience](https://github.com/gmaxxxie/omarchy-tablet-experience),
for a 2-in-1 where the rest (laptop/tablet mode switching, handwriting, window
management, bar decluttering) is noise.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

## What it does

- **Virtual keyboard** — `wvkbd-deskintl`, a wlroots-native keyboard with
  **Ctrl / Super / Alt / Shift / AltGr**, **F1–F12**, a **number row** (Chinese
  candidate selection) and **arrows**. Built for the tablet with a visible
  **▼ collapse key** so it can be folded away anywhere. Toggle with `SUPER+U`,
  the bar **⌨** button, or
  `omarchy-shell maxt.tablet-lite keyboardToggle`. wvkbd is the **only**
  backend: when the lite build is missing the helper says so instead of
  silently switching to a keyboard with different modifiers. The bar's
  keyboard highlight follows Hyprland's `openlayer` / `closelayer` events, so
  folding the keyboard away with its own **▼** key lights up immediately.
- **Voice input** — the bar **🎤** button opens a bottom hold-to-talk overlay.
  Press & hold → `omarchy dictation start`, release → `omarchy dictation stop`:
  the same commands the `ALT+SPACE` / `Alt_R` / `F9` hotkeys use, so Omarchy
  4.5 owns the backend choice (voxtype, superwhisper, …) and the touch button
  cannot drift from the keyboard shortcuts. Without a configured backend the
  overlay falls back to `voxtype record start|stop`. The text is typed at the
  cursor with `wtype` (CJK works in terminals and every toolkit). **Delete /
  Clear / Enter** fix or submit the line; a left-side **caret pad** moves through
  it; the expandable **CLI keys** grid sends `esc` `/` `tab` `⇧tab` `⌃C` `⌃D`
  `⌃J` `⌃T` for pi / codex CLI on a touch-only screen.
- Voice and keyboard are **mutually exclusive**: opening one closes the other.
- **CLI keys + caret pad are voice-mode only** — they appear with the
  hold-to-talk overlay, where there is no keyboard. With the keyboard up they
  are hidden: the keyboard itself already carries Esc / Tab / Ctrl / arrows.
- **Rotation** — **one** bar button (**⟳**) opens a picker: **Auto (sensor)**,
  the default, plus 0° / 90° / 180° / 270° and ⟲/⟳ 90° steps — so the bar no
  longer needs a second compass icon. `SUPER+SHIFT+R` still steps the display.
  Picking an angle turns sensor following off; Auto hands the screen back to
  `tlit-orient` (sysfs accelerometer, calibrated for the ThinkPad X12), which
  runs as **one long-lived reader** and reports only when the posture changes
  (no per-second process spawn). Every rotation **preserves the monitor scale**
  and keeps Hyprland's **touch calibration matrix** in step (`tlit-rotate`).
  The chosen angle and the auto flag are kept by `tlit-state` and survive shell
  restarts.

- **Lock screen** — the keyboard **auto-raises when the session locks** for
  password entry (fingerprint stays available), rendered above the Omarchy
  lock surface via `above_lock`. A floating **⌨** button right of the password
  field re-invokes it after the keyboard's **▼** key folds it away, and it is
  put back down on unlock. The keyboard is pre-started hidden at shell start
  so raising it under the lock never has to connect a new Wayland client.

- **Portrait-folded bar controls** — at 90°/270° the three touch icons
  (keyboard / voice / rotate) collapse into **one tablet button** whose popup
  carries the same actions at touch size; landscape keeps the direct one-tap
  icons. This stops the icons colliding with the
  clock on the narrower portrait bar.

Deliberately absent: laptop/tablet state machine, keyboard-auto-switch,
handwriting, window management, bar decluttering, multi-touch gestures (the
touch-swipe keyboard daemon is gone — the keyboard's ▼ key, `SUPER+U` and the
bar button cover it), SDDM greeter changes (the lock screen is supported).

## Requirements

- Omarchy 4.x (Quickshell shell) + Hyprland 0.56+ (Lua config API), Arch-based.
- `wtype` and a dictation backend (Omarchy 4.5's `omarchy dictation` ships
  voxtype support: AUR `voxtype-bin`, `omarchy-install-dictation-voxtype`).
- Build deps for the wvkbd build (`cairo pango wayland libxkbcommon`; already
  present on most Omarchy installs).
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
| `--no-wvkbd` | skip the build (the keyboard stays unavailable until built) |
| `--dry-run` | preview everything, change nothing |
| `--verify` | post-install self-check (read-only) |
| `--clean-legacy` | delete what the superseded full plugin left behind (its `texp-*` helpers, the ~90 MB handwriting models, the disabled hypr file) |

Nothing outside `$HOME` is written, and no sudo is needed when `wtype` is
already installed. Every modified file gets a `*.bak.<timestamp>` first.

**Reload the shell once** (or re-login) so the plugin loads fresh, then
`install.sh --verify`.

## Usage

| Action | Input |
|---|---|
| Toggle virtual keyboard | `SUPER+U` · bar **⌨** · `omarchy-shell maxt.tablet-lite keyboardToggle` |
| Fold the keyboard away | its **▼** key |
| Rotation | bar **⟳** → picker (Auto / 0° / 90° / 180° / 270° / ⟲ ⟳) · `SUPER+SHIFT+R` steps · `omarchy-shell maxt.tablet-lite rotationNext` |
| Sensor auto-rotate (default) | the picker's **Auto** row · `omarchy-shell maxt.tablet-lite autoRotateToggle` |
| Set an exact angle | the picker's angle row · `omarchy-shell maxt.tablet-lite setRotation 0|1|2|3|auto` |
| Portrait bar | the three icons fold into one **tablet** button → popup with keyboard / voice / rotation |
| Lock screen keyboard | raises automatically on lock; floating **⌨** button right of the password field; **▼** folds it |
| Open/close voice input | bar **🎤** · `omarchy-shell maxt.tablet-lite voiceInputToggle` |
| Dictate | press & hold the big mic, release to transcribe |
| Fix the text | **Delete** (BackSpace) / **Clear** (select-all+delete; readline `Ctrl+A`+`Ctrl+K` in terminals) / **Enter** |
| Move the caret | the left-side **← → ↑ ↓** pad |
| Agent keys (pi / codex) | **CLI keys ▲** → `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T` |

IPC: `getState` · `voiceInputToggle|Show|Hide` · `keyboardToggle|Show|Hide` ·
`cliKeysToggle` · `clearNow` · `rotationNext|rotateLeft|rotateRight` ·
`setRotation <auto|0|1|2|3>` · `autoRotateToggle` · `setAutoOrient <on|off>`
(`omarchy-shell maxt.tablet-lite <method>`).

## Files

```
Service.qml             QML service: voice overlay, caret/CLI pad, VK state
BarWidget.qml           bar buttons: ⌨ keyboard + 🎤 voice
scripts/tlit-vk         keyboard toggle/show/hide (wvkbd only)
scripts/tlit-install-wvkbd  user-local wvkbd-deskintl build (pinned v0.21 + SHA-256)
scripts/tlit-rotate     rotate display + touch matrix, preserve scale
scripts/tlit-state      rotation + auto preference file (survives restarts)
scripts/tlit-orient     IIO accelerometer posture probe (auto-rotate)
scripts/tlit-vtext      voxtype post-processing (technical-term table)
scripts/tlit-mousehop   hand a software-KVM input capture back before typing
tools/helper-drift      is the copy shared with the full plugin still the same code?
config/hypr/tablet-lite.lua  SUPER+U + SUPER+SHIFT+R + above_lock rule
config/wvkbd/wvkbd-hide-key.patch  ▼ collapse key
config/voxtype/replacements.tsv    default replacement table
```

Helpers are installed in `~/.local/bin` as `tlit-*`, deliberately apart from
the full plugin's `texp-*` set: both plugins can be installed side by side
without one overwriting the other's keyboard helper.

`mousehop`, `rotate` and `vtext` are literally the same program as the full
plugin's `texp-*` copies (only the prefix differs); `vk`, `orient`,
`install-wvkbd` and `state` are lite-only. `tools/helper-drift` checks the three
shared ones against a full-plugin checkout (`$TEXP_UPSTREAM`, default
`../omarchy-tablet-experience`) and `--sync` copies the lite version over,
prefix renamed — so a fix is written once.

## Uninstall

```sh
~/.config/omarchy/plugins/maxt.tablet-lite/uninstall.sh
omarchy plugin remove maxt.tablet-lite
```

## License

MIT — see [LICENSE](LICENSE). Derived from omarchy-tablet-experience by the
same author.

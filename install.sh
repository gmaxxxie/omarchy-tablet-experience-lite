#!/usr/bin/env bash
# ============================================================================
# install.sh — Tablet Lite: system-side setup for the voice + keyboard subset.
#
# The QML plugin itself installs with the standard Omarchy one-liner:
#     omarchy plugin add https://github.com/gmaxxxie/omarchy-tablet-experience-lite.git --enable
# (the repo root IS the plugin folder; see manifest.json)
#
# This script covers the non-QML parts and is safe to run from either the dev
# clone or the installed plugin directory:
#
#   1. helper scripts -> ~/.local/bin/tlit-vk, tlit-rotate, tlit-orient,
#      tlit-state, tlit-install-wvkbd, tlit-vtext, tlit-mousehop,
#      tlit-mousehop-toggle
#      (the tlit- prefix keeps them apart from the full plugin's texp-* set)
#   2. wvkbd-deskintl -> a user-local build with the ▼ collapse key
#      (~/.local/bin/wvkbd-deskintl; it is the only keyboard backend)
#   3. Hyprland hooks  -> SUPER+U (virtual keyboard), SUPER+SHIFT+R (rotation)
#      and above_lock for wvkbd in ~/.config/hypr/tablet-lite.lua, required
#      from hyprland.lua
#   4. folio touchpad rescue -> /usr/local/bin/tlit-folio-touchpad plus one
#      systemd unit and one udev rule, so the folio keyboard's touchpad repairs
#      itself after being detached and snapped back on
#   5. voxtype wiring  -> post-processing (tech-term replacements) and the
#      mousehop release hook right before typing
#   6. mousehop KVM    -> the maxt.mousehop bar widget (its own plugin folder in
#      this repo, installed next to maxt.tablet-lite so either can be removed
#      alone) and ~/.config/hypr/mousehop.lua with SUPER+SHIFT+K, required
#      from hyprland.lua
#
# Everything is reversible: modified files get *.bak.<timestamp> backups and
# uninstall.sh undoes every change. Nothing writes outside $HOME except the
# folio touchpad rescue (3 system files); that, and the wtype install, need
# sudo (skip them with --no-system and --no-packages).
#
# Usage:
#   ./install.sh                 install scripts + hooks + touchpad rescue + wvkbd
#   ./install.sh --no-packages   never invoke pacman (wtype)
#   ./install.sh --no-system     skip the touchpad rescue (no sudo, all inside $HOME)
#   ./install.sh --no-wvkbd      skip the wvkbd build (keyboard unavailable until built)
#   ./install.sh --dry-run       preview only, change nothing
#   ./install.sh --verify        post-install self-check (read-only)
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.config/omarchy/plugins}"
# The folio touchpad rescue is the only part that lives outside $HOME.
SYSTEM_BIN="${SYSTEM_BIN:-/usr/local/bin}"
UNIT_DIR="${UNIT_DIR:-/etc/systemd/system}"
UDEV_DIR="${UDEV_DIR:-/etc/udev/rules.d}"
DRY_RUN=0
DO_PACKAGES=1
DO_SYSTEM=1
BUILD_WVKBD=1
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --no-packages) DO_PACKAGES=0 ;;
    --no-system)   DO_SYSTEM=0 ;;
    --no-wvkbd)    BUILD_WVKBD=0 ;;
    --verify)      VERIFY=1 ;;
    -h|--help)     awk 'NR>2 && /^# =====/{exit} NR>2{sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m  !! \033[0m %s\n' "$*"; }
run()  { if [ "$DRY_RUN" -eq 1 ]; then printf '    would run: %s\n' "$*"; else "$@"; fi }

# Session-environment fallback for coding-agent / ssh invocations: the user bus
# (systemctl --user, gsettings) needs these when the caller has no graphical
# session environment of its own.
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] \
    && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

backup_file() { # $1 path
  local f="$1"
  [ -e "$f" ] || return 0
  local stamp; stamp="$(date +%Y%m%d%H%M%S)"
  local dest="$f.bak.$stamp"
  local n=1
  while [ -e "$dest" ]; do dest="$f.bak.$stamp-$n"; n=$((n + 1)); done
  run cp -a "$f" "$dest"
  log "backup: $dest"
}

# System files (outside $HOME) are copied only when they differ, so re-running
# install.sh does not ask for a password for nothing.
install_system_file() { # $1 src $2 dest $3 mode $4 label
  local src="$1" dest="$2" mode="$3" label="$4"
  if [ -e "$dest" ] && cmp -s "$src" "$dest"; then
    ok "$label up to date"
    return 0
  fi
  run sudo install -D -m "$mode" "$src" "$dest"
  log "$label -> $dest"
  system_changed=1
}

# ------------------------------------------------------------- verify only
if [ "$VERIFY" -eq 1 ]; then
  log "Tablet Lite self-check (read-only)"
  fail=0

  for s in tlit-vk tlit-vtext tlit-mousehop tlit-mousehop-toggle tlit-install-wvkbd tlit-rotate tlit-orient tlit-state; do
    if [ -x "$BIN_DIR/$s" ]; then ok "helper $BIN_DIR/$s"; else bad "helper missing: $BIN_DIR/$s"; fail=1; fi
  done

  vk_check="$("$BIN_DIR/tlit-install-wvkbd" --check 2>/dev/null)"
  if [ -n "$vk_check" ]; then
    ok "keyboard: $vk_check"
  elif [ -e "$BIN_DIR/wvkbd-deskintl" ] || command -v wvkbd-deskintl >/dev/null 2>&1; then
    warn "wvkbd-deskintl present but not the pinned lite build — run $BIN_DIR/tlit-install-wvkbd"
  else
    bad "wvkbd-deskintl is not installed — run $BIN_DIR/tlit-install-wvkbd"; fail=1
  fi

  if [ -f "$HYPR_DIR/tablet-lite.lua" ]; then ok "hypr config $HYPR_DIR/tablet-lite.lua"; else bad "hypr config missing"; fail=1; fi
  if grep -qF 'require("hypr.tablet-lite")' "$HYPR_DIR/hyprland.lua" 2>/dev/null; then
    ok "hyprland.lua requires hypr.tablet-lite"
  else
    bad "hyprland.lua does not require hypr.tablet-lite"; fail=1
  fi
  if grep -qF 'maxt.tablet-lite rotationNext' "$HYPR_DIR/tablet-lite.lua" 2>/dev/null; then
    ok "SUPER+SHIFT+R -> rotationNext"
  else
    bad "rotation keybind missing from $HYPR_DIR/tablet-lite.lua"; fail=1
  fi
  if grep -qF 'maxt-tablet-vk-toggle' "$HYPR_DIR/tablet-lite.lua" 2>/dev/null; then
    ok "lock-screen VK button above_lock rule"
  else
    bad "lock-screen VK layer rule missing from $HYPR_DIR/tablet-lite.lua"; fail=1
  fi
  if "$BIN_DIR/tlit-orient" --json >/dev/null 2>&1; then
    ok "accelerometer readable (tlit-orient)"
  else
    warn "tlit-orient could not read an IIO accelerometer — auto-rotate will not work"
  fi

  if command -v voxtype >/dev/null 2>&1; then
    if backend="$(omarchy-default-dictation 2>/dev/null)" && [ -n "$backend" ]; then
      ok "dictation backend: $backend (the mic button drives omarchy dictation)"
    else
      warn "no dictation backend selected — Setup > Defaults > Dictation (the mic button says so)"
    fi
    pp="$(voxtype config get output.post_process.command 2>/dev/null | tr -d '"')"
    if [ "$pp" = "$BIN_DIR/tlit-vtext" ]; then
      ok "voxtype post_process.command -> tlit-vtext"
    else
      bad "voxtype post_process.command not wired (got: ${pp:-unset})"; fail=1
    fi
    pre="$(voxtype config get output.pre_output_command 2>/dev/null | tr -d '"')"
    if [ "$pre" = "$BIN_DIR/tlit-mousehop release" ]; then
      ok "voxtype pre_output_command -> tlit-mousehop release"
    elif [ -z "$pre" ] || [ "$pre" = "null" ]; then
      warn "voxtype pre_output_command is not wired (mousehop release hook)"
    elif [ "${pre##*/}" = "texp-mousehop release" ]; then
      warn "voxtype pre_output_command still points at the old texp-mousehop — re-run install.sh"
    else
      warn "voxtype pre_output_command belongs to someone else ($pre) — left alone"
    fi
    if systemctl --user is-active voxtype.service >/dev/null 2>&1; then
      ok "voxtype service running"
    else
      bad "voxtype service not running — systemctl --user start voxtype"; fail=1
    fi
  else
    warn "voxtype not installed — voice input needs it (voxtype-bin from the AUR)"
  fi

  if command -v omarchy-shell >/dev/null 2>&1 \
      && [ -n "$(omarchy-shell maxt.tablet-lite getState 2>/dev/null)" ]; then
    ok "plugin IPC answers (maxt.tablet-lite)"
  else
    warn "plugin IPC does not answer yet — reload the shell / re-login"
  fi

  if [ -f "$PLUGIN_DIR/maxt.mousehop/manifest.json" ]; then
    ok "mousehop widget $PLUGIN_DIR/maxt.mousehop"
  else
    bad "mousehop widget not installed — re-run install.sh"; fail=1
  fi
  if omarchy plugin list 2>/dev/null | grep -qE '^maxt\.mousehop[[:space:]]+enabled'; then
    ok "mousehop widget enabled on the bar"
  else
    bad "maxt.mousehop is not enabled — omarchy plugin enable maxt.mousehop right"; fail=1
  fi
  if [ -f "$HYPR_DIR/mousehop.lua" ]; then
    ok "hypr config $HYPR_DIR/mousehop.lua"
  else
    bad "hypr config missing: $HYPR_DIR/mousehop.lua"; fail=1
  fi
  if grep -qF 'require("hypr.mousehop")' "$HYPR_DIR/hyprland.lua" 2>/dev/null; then
    ok "hyprland.lua requires hypr.mousehop"
  else
    bad "hyprland.lua does not require hypr.mousehop"; fail=1
  fi
  if grep -qF 'tlit-mousehop-toggle toggle' "$HYPR_DIR/mousehop.lua" 2>/dev/null; then
    ok "SUPER+SHIFT+K -> mousehop on/off"
  else
    bad "mousehop keybind missing from $HYPR_DIR/mousehop.lua"; fail=1
  fi
  if "$BIN_DIR/tlit-mousehop-toggle" status >/dev/null 2>&1; then
    ok "mousehop state: $("$BIN_DIR/tlit-mousehop-toggle" status 2>/dev/null | head -1)"
  else
    warn "mousehop state unreadable (daemon down, or no peer configured)"
  fi

  # folio touchpad rescue (system files; read-only)
  if [ -x "$SYSTEM_BIN/tlit-folio-touchpad" ] \
      && [ -e "$UNIT_DIR/tlit-folio-touchpad.service" ] \
      && [ -e "$UDEV_DIR/99-tlit-folio-touchpad.rules" ]; then
    ok "folio touchpad rescue installed (helper + unit + udev rule)"
    if compgen -G '/sys/bus/hid/devices/0003:17EF:60FE.*' >/dev/null; then
      tp_node=""
      for e in /sys/bus/hid/devices/0003:17EF:60FE.*/input/input*/event*; do
        [ -e "$e" ] || continue
        if udevadm info --query=property --name="/dev/input/$(basename "$e")" 2>/dev/null \
            | grep -q '^ID_INPUT_TOUCHPAD=1'; then
          tp_node="/dev/input/$(basename "$e")"
        fi
      done
      if [ -n "$tp_node" ]; then
        ok "folio touchpad node present: $tp_node"
      else
        warn "folio attached but no touchpad node — run: sudo tlit-folio-touchpad"
      fi
    fi
  else
    warn "folio touchpad rescue missing (skipped with --no-system?) — re-run install.sh"
  fi

  if [ "$fail" -eq 0 ]; then
    log "self-check passed"
  else
    warn "self-check found problems (see above)"; exit 1
  fi
  exit 0
fi

[ "$DRY_RUN" -eq 1 ] && log "DRY RUN — nothing will be changed"

# --------------------------------------------------------------- packages
# wtype is the only package the lite feature set needs: it sends the voice
# pad's Delete / Clear / Enter, the caret arrows and the CLI keys. The keyboard
# is the user-local wvkbd build, and the dictation backend is AUR-only and is
# reported rather than installed silently.
if [ "$DO_PACKAGES" -eq 1 ] && command -v pacman >/dev/null 2>&1; then
  REQUIRED=(wtype)
  MISSING=()
  for p in "${REQUIRED[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || MISSING+=("$p")
  done
  if [ "${#MISSING[@]}" -gt 0 ]; then
    log "installing packages: ${MISSING[*]}"
    run sudo pacman -S --needed --noconfirm "${MISSING[@]}"
  else
    ok "packages present: ${REQUIRED[*]}"
  fi
fi

# ---------------------------------------------------------- helper scripts
log "installing helper scripts -> $BIN_DIR"
run mkdir -p "$BIN_DIR"
for src in "$REPO_ROOT"/scripts/tlit-*; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  # tlit-folio-touchpad runs as root from udev/systemd, so it goes to
  # $SYSTEM_BIN (see the touchpad rescue section) instead of ~/.local/bin.
  [ "$name" = "tlit-folio-touchpad" ] && continue
  run install -m 0755 "$src" "$BIN_DIR/$name"
done

# ------------------------------------------------------------- data files
# The installed tlit-install-wvkbd is in ~/.local/bin and cannot see the repo;
# keep the patch it applies in a stable data directory.
LITE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/tablet-lite"
run mkdir -p "$LITE_DATA"
run install -m 0644 "$REPO_ROOT/config/wvkbd/wvkbd-hide-key.patch" "$LITE_DATA/wvkbd-hide-key.patch"

# ------------------------------------------------------------- wvkbd build
if [ "$BUILD_WVKBD" -eq 1 ]; then
  if [ -x "$BIN_DIR/tlit-install-wvkbd" ]; then
    log "building wvkbd-deskintl (lite ▼ build; best-effort)"
    run "$BIN_DIR/tlit-install-wvkbd" || warn "wvkbd build skipped — the keyboard stays unavailable until it is built"
  else
    warn "tlit-install-wvkbd missing — skipping the keyboard build"
  fi
else
  warn "--no-wvkbd: no keyboard until tlit-install-wvkbd is run"
fi

# ------------------------------------------------------------ Hyprland hooks
log "installing Hyprland hooks -> $HYPR_DIR"
run mkdir -p "$HYPR_DIR"
if [ -f "$HYPR_DIR/tablet-lite.lua" ] \
    && ! cmp -s "$REPO_ROOT/config/hypr/tablet-lite.lua" "$HYPR_DIR/tablet-lite.lua"; then
  backup_file "$HYPR_DIR/tablet-lite.lua"
fi
run install -m 0644 "$REPO_ROOT/config/hypr/tablet-lite.lua" "$HYPR_DIR/tablet-lite.lua"

if [ -f "$HYPR_DIR/hyprland.lua" ]; then
  if ! grep -qF 'require("hypr.tablet-lite")' "$HYPR_DIR/hyprland.lua"; then
    backup_file "$HYPR_DIR/hyprland.lua"
    run sh -c "printf '\nrequire(\"hypr.tablet-lite\")\n' >> '$HYPR_DIR/hyprland.lua'"
    log "hyprland.lua: added require(\"hypr.tablet-lite\")"
  else
    ok "hyprland.lua already requires hypr.tablet-lite"
  fi
else
  warn "$HYPR_DIR/hyprland.lua not found — add require(\"hypr.tablet-lite\") yourself"
fi

# ------------------------------------------------------- mousehop bar widget
# The KVM switch is not a tablet feature, so it ships as its own plugin folder
# (mousehop/ in this repo) installed next to maxt.tablet-lite rather than inside
# it: either plugin can then be removed without touching the other.
MH_SRC="$REPO_ROOT/mousehop"
MH_DST="$PLUGIN_DIR/maxt.mousehop"

log "installing the mousehop bar widget -> $MH_DST"
run mkdir -p "$MH_DST"
for f in manifest.json BarWidget.qml README.md; do
  if [ ! -f "$MH_SRC/$f" ]; then
    warn "missing $MH_SRC/$f"
    continue
  fi
  if [ -f "$MH_DST/$f" ] && ! cmp -s "$MH_SRC/$f" "$MH_DST/$f"; then
    backup_file "$MH_DST/$f"
  fi
  run install -m 0644 "$MH_SRC/$f" "$MH_DST/$f"
done

if command -v omarchy >/dev/null 2>&1; then
  if run omarchy plugin enable maxt.mousehop right >/dev/null 2>&1; then
    log "mousehop widget enabled (bar, right)"
  else
    warn "could not enable maxt.mousehop — run: omarchy plugin enable maxt.mousehop right"
  fi
  # Beside the monitor indicator, away from the audio/battery cluster.
  run omarchy bar move maxt.mousehop --after omarchy.monitor >/dev/null 2>&1 || true
else
  warn "omarchy CLI not found — enable it yourself: omarchy plugin enable maxt.mousehop"
fi

# ------------------------------------------------- mousehop hyprland hook
if [ -f "$HYPR_DIR/mousehop.lua" ] \
    && ! cmp -s "$REPO_ROOT/config/hypr/mousehop.lua" "$HYPR_DIR/mousehop.lua"; then
  backup_file "$HYPR_DIR/mousehop.lua"
fi
run install -m 0644 "$REPO_ROOT/config/hypr/mousehop.lua" "$HYPR_DIR/mousehop.lua"

if [ -f "$HYPR_DIR/hyprland.lua" ]; then
  if ! grep -qF 'require("hypr.mousehop")' "$HYPR_DIR/hyprland.lua"; then
    backup_file "$HYPR_DIR/hyprland.lua"
    run sh -c "printf '\\nrequire(\"hypr.mousehop\")\\n' >> '$HYPR_DIR/hyprland.lua'"
    log "hyprland.lua: added require(\"hypr.mousehop\")"
  else
    ok "hyprland.lua already requires hypr.mousehop"
  fi
else
  warn "$HYPR_DIR/hyprland.lua not found — add require(\"hypr.mousehop\") yourself"
fi

# An older hand-added binding would fire the toggle twice per keypress.
if grep -qF 'tlit-mousehop-toggle' "$HYPR_DIR/bindings.lua" 2>/dev/null; then
  warn "SUPER+SHIFT+K is also bound in $HYPR_DIR/bindings.lua — remove that line"
fi

# --------------------------------------------------- folio touchpad rescue
# The one part that lives outside $HOME. The folio keyboard loses the touchpad's
# multitouch report channel when it is detached and snapped back on: only the
# device's legacy relative "mouse" collection keeps working, so the cursor
# still moves and clicks while tap, clickpad press and two- and three-finger
# gestures die silently. Only a driver re-bind brings it back, and that needs
# root — a oneshot unit plus a udev rule do it on every attach.
if [ "$DO_SYSTEM" -eq 1 ]; then
  log "installing folio touchpad rescue -> $SYSTEM_BIN + systemd unit + udev rule"
  if [ "$DRY_RUN" -eq 0 ] && ! sudo -n true 2>/dev/null; then
    warn "the touchpad rescue lives in $SYSTEM_BIN, $UNIT_DIR and $UDEV_DIR — sudo may ask for a password"
  fi
  system_changed=0
  # An earlier install copied the helper next to the user helpers; udev and
  # systemd run it as root, so it belongs to $SYSTEM_BIN now.
  if [ -e "$BIN_DIR/tlit-folio-touchpad" ] \
      && cmp -s "$REPO_ROOT/scripts/tlit-folio-touchpad" "$BIN_DIR/tlit-folio-touchpad"; then
    run rm -f "$BIN_DIR/tlit-folio-touchpad"
    log "removed stale user copy: $BIN_DIR/tlit-folio-touchpad"
  fi
  install_system_file "$REPO_ROOT/scripts/tlit-folio-touchpad" \
    "$SYSTEM_BIN/tlit-folio-touchpad" 0755 "touchpad rescue helper"
  install_system_file "$REPO_ROOT/config/systemd/tlit-folio-touchpad.service" \
    "$UNIT_DIR/tlit-folio-touchpad.service" 0644 "touchpad rescue unit"
  install_system_file "$REPO_ROOT/config/udev/99-tlit-folio-touchpad.rules" \
    "$UDEV_DIR/99-tlit-folio-touchpad.rules" 0644 "touchpad rescue udev rule"
  if [ "$system_changed" -eq 1 ]; then
    run sudo systemctl daemon-reload
    run sudo udevadm control --reload-rules
  else
    ok "systemd and udev already know about it (no reload needed)"
  fi
else
  warn "--no-system: the touchpad rescue is not installed (tap, clickpad press and 2/3-finger gestures stay dead after re-attaching the folio)"
fi

# ----------------------------------------------------------- voxtype wiring
if command -v voxtype >/dev/null 2>&1; then
  log "wiring voxtype (tech-term post-processing + mousehop release hook)"
  VT_CONF="$HOME/.config/voxtype"
  run mkdir -p "$VT_CONF"
  if [ ! -f "$VT_CONF/replacements.tsv" ]; then
    run install -m 0644 "$REPO_ROOT/config/voxtype/replacements.tsv" "$VT_CONF/replacements.tsv"
    log "installed default replacement table: $VT_CONF/replacements.tsv"
  else
    ok "replacement table present (left untouched): $VT_CONF/replacements.tsv"
  fi
  run voxtype config set output.post_process.command "$BIN_DIR/tlit-vtext"
  log "voxtype output.post_process.command -> $BIN_DIR/tlit-vtext"

  # The mousehop release hook runs right before voxtype types, so a software
  # KVM capture is handed back first. `voxtype config set` knows the key now
  # (it is in the schema), which is why the old config-file editor is gone.
  pre="$(voxtype config get output.pre_output_command 2>/dev/null | tr -d '"')"
  want="$BIN_DIR/tlit-mousehop release"
  case "$pre" in
    "$want") ok "voxtype pre_output_command already -> $want" ;;
    ""|null)
      run voxtype config set output.pre_output_command "$want"
      log "voxtype output.pre_output_command -> $want"
      ;;
    *texp-mousehop*)
      # Pre-1.5 install: the hook points at the old helper name.
      run voxtype config set output.pre_output_command "$want"
      log "voxtype output.pre_output_command migrated ($pre -> $want)"
      ;;
    *) warn "voxtype pre_output_command is set by the user ($pre) — the mousehop release hook stays manual" ;;
  esac

  run systemctl --user restart voxtype 2>/dev/null \
    || warn "could not restart voxtype via systemctl --user — run: systemctl --user restart voxtype"
  log "voxtype wiring done"
else
  warn "voxtype is not installed — voice input will not work until it is (AUR: voxtype-bin)"
fi

# ------------------------------------------------------------------ done
cat <<EOF

Done.

  Keyboard : SUPER+U, the bar ⌨ button, or
             omarchy-shell maxt.tablet-lite keyboardToggle
  Voice    : the bar 🎤 button (press & hold the big mic), or
             omarchy-shell maxt.tablet-lite voiceInputToggle
  Rotation : the bar ⟳ button (picker: auto / 0° / 90° / 180° / 270°),
             SUPER+SHIFT+R steps 90°
  Lock     : the keyboard auto-raises on lock; the floating ⌨ button right
             of the password field re-invokes it after ▼ folds it away
  KVM      : the bar ⇄ button (red = armed) or SUPER+SHIFT+K; off = the
             pointer and keyboard never leave this machine
  Touchpad : the folio keyboard repairs itself after being re-attached (udev
             rule + tlit-folio-touchpad); by hand: sudo tlit-folio-touchpad

Reload the shell once so the plugin loads fresh (or re-login), then check with:
  ./install.sh --verify
EOF

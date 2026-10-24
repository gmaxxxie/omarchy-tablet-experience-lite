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
#   1. helper daemons -> ~/.local/bin/texp-vk, texp-vtext, texp-voxtype-wire,
#      texp-mousehop, texp-install-wvkbd, texp-rotate, texp-orient
#   2. wvkbd-deskintl -> a user-local build with the ▼ collapse key
#      (~/.local/bin/wvkbd-deskintl; squeekboard stays as the fallback)
#   3. Hyprland hooks  -> SUPER+U (virtual keyboard), SUPER+SHIFT+R (rotation)
#      and above_lock for wvkbd in ~/.config/hypr/tablet-lite.lua, required
#      from hyprland.lua
#   4. voxtype wiring  -> post-processing (tech-term replacements) and the
#      mousehop release hook right before typing
#
# Everything is reversible: modified files get *.bak.<timestamp> backups and
# uninstall.sh undoes every change. No sudo is needed when the few packages are
# already present (and none of the install steps write outside $HOME).
#
# Usage:
#   ./install.sh                 install scripts + hooks + wvkbd build
#   ./install.sh --no-packages   never invoke pacman
#   ./install.sh --no-wvkbd      skip the wvkbd build (squeekboard fallback)
#   ./install.sh --dry-run       preview only, change nothing
#   ./install.sh --verify        post-install self-check (read-only)
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
DRY_RUN=0
DO_PACKAGES=1
BUILD_WVKBD=1
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --no-packages) DO_PACKAGES=0 ;;
    --no-wvkbd)    BUILD_WVKBD=0 ;;
    --verify)      VERIFY=1 ;;
    -h|--help)     sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ------------------------------------------------------------- verify only
if [ "$VERIFY" -eq 1 ]; then
  log "Tablet Lite self-check (read-only)"
  fail=0

  for s in texp-vk texp-vtext texp-voxtype-wire texp-mousehop texp-install-wvkbd texp-rotate texp-orient; do
    if [ -x "$BIN_DIR/$s" ]; then ok "helper $BIN_DIR/$s"; else bad "helper missing: $BIN_DIR/$s"; fail=1; fi
  done

  if [ -x "$HOME/.local/bin/wvkbd-deskintl" ] \
      && grep -q $'\xE2\x96\xBC' "$HOME/.local/bin/wvkbd-deskintl" 2>/dev/null; then
    ok "wvkbd-deskintl lite build with ▼ ($HOME/.local/bin/wvkbd-deskintl)"
  elif command -v wvkbd-deskintl >/dev/null 2>&1; then
    warn "wvkbd-deskintl present but without the lite ▼ build — run $BIN_DIR/texp-install-wvkbd"
  elif command -v squeekboard >/dev/null 2>&1; then
    warn "wvkbd-deskintl not built — squeekboard fallback will be used"
  else
    bad "no virtual-keyboard backend (wvkbd-deskintl or squeekboard)"; fail=1
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
  if "$BIN_DIR/texp-orient" --json >/dev/null 2>&1; then
    ok "accelerometer readable (texp-orient)"
  else
    warn "texp-orient could not read an IIO accelerometer — auto-rotate will not work"
  fi

  if command -v voxtype >/dev/null 2>&1; then
    pp="$(voxtype config get output.post_process.command 2>/dev/null | tr -d '"')"
    if [ "$pp" = "$BIN_DIR/texp-vtext" ]; then
      ok "voxtype post_process.command -> texp-vtext"
    else
      bad "voxtype post_process.command not wired (got: ${pp:-unset})"; fail=1
    fi
    if [ -x "$BIN_DIR/texp-voxtype-wire" ] \
        && "$BIN_DIR/texp-voxtype-wire" --bin "$BIN_DIR" --check >/dev/null 2>&1; then
      ok "voxtype pre_output_command -> texp-mousehop release"
    else
      warn "voxtype pre_output_command is not wired (mousehop release hook)"
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

  [ "$fail" -eq 0 ] && log "self-check passed" || { warn "self-check found problems (see above)"; exit 1; }
  exit 0
fi

[ "$DRY_RUN" -eq 1 ] && log "DRY RUN — nothing will be changed"

# --------------------------------------------------------------- packages
# Only the fallback keyboard and the (optional) touch-swipe daemon's evdev
# binding are packages. voxtype itself is AUR-only and is reported, not
# installed silently.
if [ "$DO_PACKAGES" -eq 1 ] && command -v pacman >/dev/null 2>&1; then
  REQUIRED=(squeekboard wtype)
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
for src in "$REPO_ROOT"/scripts/texp-*; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  run install -m 0755 "$src" "$BIN_DIR/$name"
done

# ------------------------------------------------------------- data files
# The installed texp-install-wvkbd is in ~/.local/bin and cannot see the repo;
# keep the patch it applies in a stable data directory.
LITE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/tablet-lite"
run mkdir -p "$LITE_DATA"
run install -m 0644 "$REPO_ROOT/config/wvkbd/wvkbd-hide-key.patch" "$LITE_DATA/wvkbd-hide-key.patch"

# ------------------------------------------------------------- wvkbd build
if [ "$BUILD_WVKBD" -eq 1 ]; then
  if [ -x "$BIN_DIR/texp-install-wvkbd" ]; then
    log "building wvkbd-deskintl (lite ▼ build; best-effort, squeekboard stays)"
    run "$BIN_DIR/texp-install-wvkbd" || warn "wvkbd build skipped — squeekboard fallback remains"
  else
    warn "texp-install-wvkbd missing — skipping the keyboard build"
  fi
else
  warn "--no-wvkbd: leaving the keyboard to the squeekboard fallback"
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
  run voxtype config set output.post_process.command "$BIN_DIR/texp-vtext"
  log "voxtype output.post_process.command -> $BIN_DIR/texp-vtext"

  if [ -x "$BIN_DIR/texp-voxtype-wire" ]; then
    VW_RC=0
    run "$BIN_DIR/texp-voxtype-wire" --bin "$BIN_DIR" || VW_RC=$?
    case $VW_RC in
      0) : ;;
      2) warn "voxtype pre_output_command is set by the user — the mousehop release hook stays manual" ;;
      *) warn "could not wire voxtype pre_output_command (exit $VW_RC)" ;;
    esac
  fi

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
  Rotation : SUPER+SHIFT+R, or the bar ⟳ button (click = next 90°,
             right-click = sensor auto-rotate on/off)

Reload the shell once so the plugin loads fresh (or re-login), then check with:
  ./install.sh --verify
EOF

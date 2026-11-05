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
#   1. helper scripts -> ~/.local/bin/tlit-vk, tlit-vtext, tlit-mousehop,
#      tlit-install-wvkbd, tlit-rotate, tlit-orient
#      (the tlit- prefix keeps them apart from the full plugin's texp-* set)
#   2. wvkbd-deskintl -> a user-local build with the ▼ collapse key
#      (~/.local/bin/wvkbd-deskintl; it is the only keyboard backend)
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
#   ./install.sh --no-wvkbd      skip the wvkbd build (keyboard unavailable until built)
#   ./install.sh --dry-run       preview only, change nothing
#   ./install.sh --verify        post-install self-check (read-only)
#   ./install.sh --clean-legacy  remove what the superseded full plugin
#                                (maxt.tablet-experience) left behind:
#                                its texp-* helpers, the ~/local/share/texp-ink
#                                handwriting models and the disabled hypr file
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
DRY_RUN=0
DO_PACKAGES=1
BUILD_WVKBD=1
VERIFY=0
CLEAN_LEGACY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --no-packages) DO_PACKAGES=0 ;;
    --no-wvkbd)    BUILD_WVKBD=0 ;;
    --verify)      VERIFY=1 ;;
    --clean-legacy) CLEAN_LEGACY=1 ;;
    -h|--help)     sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

  for s in tlit-vk tlit-vtext tlit-mousehop tlit-install-wvkbd tlit-rotate tlit-orient; do
    if [ -x "$BIN_DIR/$s" ]; then ok "helper $BIN_DIR/$s"; else bad "helper missing: $BIN_DIR/$s"; fail=1; fi
  done

  if [ -x "$HOME/.local/bin/wvkbd-deskintl" ] \
      && grep -q $'\xE2\x96\xBC' "$HOME/.local/bin/wvkbd-deskintl" 2>/dev/null; then
    ok "wvkbd-deskintl lite build with ▼ ($HOME/.local/bin/wvkbd-deskintl)"
  elif command -v wvkbd-deskintl >/dev/null 2>&1; then
    warn "wvkbd-deskintl present but without the lite ▼ build — run $BIN_DIR/tlit-install-wvkbd"
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
      warn "no omarchy dictation backend configured — the mic button falls back to 'voxtype record'"
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

  if [ "$fail" -eq 0 ] && [ ! -e "$HOME/.local/share/texp-ink" ]; then
    log "self-check passed"
  elif [ "$fail" -ne 0 ]; then
    warn "self-check found problems (see above)"; exit 1
  else
    warn "self-check passed, but the full plugin's handwriting models are still in"
    warn "  ~/.local/share/texp-ink (~90 MB) — remove with: ./install.sh --clean-legacy"
  fi
  exit 0
fi

[ "$DRY_RUN" -eq 1 ] && log "DRY RUN — nothing will be changed"

# ------------------------------------------------- legacy cleanup only
# The lite plugin keeps only what it needs. The full plugin
# (maxt.tablet-experience) and the pre-1.5 lite install left helpers, a 90 MB
# handwriting model and a disabled hypr config behind; none of it is read by
# this plugin. Explicit opt-in, because it deletes files outside the repo.
if [ "$CLEAN_LEGACY" -eq 1 ]; then
  log "cleaning leftovers of the superseded full plugin / pre-1.5 lite install"
  freed_before="$(du -scm "$HOME/.local/share/texp-ink" 2>/dev/null | tail -1 | cut -f1)"

  # Helpers that only the full plugin ever used.
  for s in texp-ink texp-ink-key texp-touch texp-window texp-close \
           texp-bar-probe texp-hw-laptop-closed texp-kbdetect \
           texp-sddm-vk texp-priv-install; do
    [ -e "$BIN_DIR/$s" ] || continue
    run rm -f "$BIN_DIR/$s" && log "removed $BIN_DIR/$s"
  done

  # The pre-1.5 lite helpers (now tlit-*). Shared names with the full plugin,
  # so they go only when that plugin is not installed.
  if [ -d "$HOME/.config/omarchy/plugins/maxt.tablet-experience" ]; then
    warn "maxt.tablet-experience is still installed — keeping the shared texp-* helpers"
  else
    for s in texp-vk texp-orient texp-rotate texp-mousehop texp-vtext \
             texp-voxtype-wire texp-install-wvkbd; do
      [ -e "$BIN_DIR/$s" ] || continue
      run rm -f "$BIN_DIR/$s" && log "removed stale helper $BIN_DIR/$s"
    done
  fi

  # Handwriting recognition models (offline PP-OCRv6, ~90 MB).
  if [ -d "$HOME/.local/share/texp-ink" ]; then
    run rm -rf "$HOME/.local/share/texp-ink"
    log "removed $HOME/.local/share/texp-ink (${freed_before:-?} MB of handwriting models)"
  fi

  # The full plugin's Hyprland hook, disabled when lite took over.
  for f in "$HYPR_DIR/tablet-experience.lua" \
           "$HYPR_DIR/tablet-experience.lua.disabled-lite"; do
    [ -e "$f" ] || continue
    run rm -f "$f" && log "removed $f"
  done

  log "legacy cleanup done"
  exit 0
fi

# --------------------------------------------------------------- packages
# wtype is the only package the lite feature set needs: the keyboard is the
# user-local wvkbd build, and voxtype itself is AUR-only and is reported, not
# installed silently.
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
  Rotation : SUPER+SHIFT+R, or the bar ⟳ button (next 90°)
  Auto     : the bar 🧭 button (sensor-following on/off)
  Lock     : the keyboard auto-raises on lock; the floating ⌨ button right
             of the password field re-invokes it after ▼ folds it away

Reload the shell once so the plugin loads fresh (or re-login), then check with:
  ./install.sh --verify
EOF

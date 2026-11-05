#!/usr/bin/env bash
# ============================================================================
# uninstall.sh — reverse everything install.sh did for Tablet Lite.
#
# Safety rules:
#   - files are removed only when they byte-match the repo copy (user edits are
#     kept and reported instead)
#   - packages are not touched (nothing was installed: the keyboard is a
#     user-local build, dictation belongs to Omarchy)
#   - the user's voxtype replacement table is user data — left in place
#   - the folio touchpad rescue (helper + unit + udev rule) is the only system
#     state; it is removed with sudo under the same byte-match rule
#
# Usage:
#   ./uninstall.sh             undo install.sh changes
#   ./uninstall.sh --dry-run   preview only, change nothing
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.config/omarchy/plugins}"
SYSTEM_BIN="${SYSTEM_BIN:-/usr/local/bin}"
UNIT_DIR="${UNIT_DIR:-/etc/systemd/system}"
UDEV_DIR="${UDEV_DIR:-/etc/udev/rules.d}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
run()  { if [ "$DRY_RUN" -eq 1 ]; then printf '    would run: %s\n' "$*"; else "$@"; fi }

remove_if_same() { # $1 path $2 repo copy $3 label
  local file="$1" repo="$2" label="$3"
  [ -e "$file" ] || return 0
  if cmp -s "$file" "$repo"; then
    run rm -f "$file"; log "removed $label: $file"
  else
    warn "$label differs from the repo copy — left in place: $file"
  fi
}

# Same rule for the system files install.sh copies with sudo.
remove_if_same_root() { # $1 path $2 repo copy $3 label
  local file="$1" repo="$2" label="$3"
  [ -e "$file" ] || return 0
  if cmp -s "$file" "$repo"; then
    run sudo rm -f "$file"; log "removed $label: $file"; system_changed=1
  else
    warn "$label differs from the repo copy — left in place: $file"
  fi
}

[ "$DRY_RUN" -eq 1 ] && log "DRY RUN — nothing will be changed"

# ------------------------------------------------ hyprland hooks
for f in "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/autostart.lua"; do
  [ -f "$f" ] || continue
  if grep -qF 'require("hypr.tablet-lite")' "$f"; then
    run sed -i '\|require("hypr.tablet-lite")|d' "$f"
    log "removed from $f: require(\"hypr.tablet-lite\")"
  fi
  if grep -qF 'require("hypr.mousehop")' "$f"; then
    run sed -i '\|require("hypr.mousehop")|d' "$f"
    log "removed from $f: require(\"hypr.mousehop\")"
  fi
done
remove_if_same "$HYPR_DIR/tablet-lite.lua" \
  "$REPO_ROOT/config/hypr/tablet-lite.lua" "hypr config"
remove_if_same "$HYPR_DIR/mousehop.lua" \
  "$REPO_ROOT/config/hypr/mousehop.lua" "hypr config (mousehop)"

# ------------------------------------------------ mousehop bar widget
# Its own plugin folder: removing it must not touch maxt.tablet-lite.
MH_DST="$PLUGIN_DIR/maxt.mousehop"
if command -v omarchy >/dev/null 2>&1 \
    && omarchy plugin list 2>/dev/null | grep -qE '^maxt\.mousehop[[:space:]]+enabled'; then
  run omarchy plugin disable maxt.mousehop >/dev/null 2>&1 \
    && log "mousehop widget disabled on the bar" \
    || warn "could not disable maxt.mousehop — run: omarchy plugin disable maxt.mousehop"
fi
for f in manifest.json BarWidget.qml README.md; do
  remove_if_same "$MH_DST/$f" "$REPO_ROOT/mousehop/$f" "mousehop widget file"
done
[ -d "$MH_DST" ] && run rmdir --ignore-fail-on-non-empty "$MH_DST"

# ------------------------------------------------ voxtype wiring
if command -v voxtype >/dev/null 2>&1; then
  pre="$(voxtype config get output.pre_output_command 2>/dev/null | tr -d '"')"
  case "$pre" in
    "$BIN_DIR/tlit-mousehop release"|*texp-mousehop*)
      run voxtype config unset output.pre_output_command
      log "voxtype: unset output.pre_output_command (was the mousehop release hook)"
      ;;
    ""|null) : ;;
    *) warn "voxtype pre_output_command is not ours ($pre) — left in place" ;;
  esac
  cur="$(voxtype config get output.post_process.command 2>/dev/null | tr -d '"')"
  if [ "$cur" = "$BIN_DIR/tlit-vtext" ]; then
    run voxtype config unset output.post_process.command
    log "voxtype: unset output.post_process.command (was $cur)"
  elif [ -n "$cur" ] && [ "$cur" != "null" ]; then
    warn "voxtype post_process.command is not ours ($cur) — left in place"
  fi
  run systemctl --user restart voxtype 2>/dev/null \
    || warn "could not restart voxtype via systemctl --user — run: systemctl --user restart voxtype"
fi

# ------------------------------------------------ helper scripts
for src in "$REPO_ROOT"/scripts/tlit-*; do
  [ -f "$src" ] || continue
  remove_if_same "$BIN_DIR/$(basename "$src")" "$src" "helper script"
done

# ------------------------------------------------ folio touchpad rescue
# The only system-side install: helper in /usr/local/bin, one systemd unit, one
# udev rule. Removed with sudo, and still only when they byte-match the repo.
if [ -e "$UNIT_DIR/tlit-folio-touchpad.service" ] \
    || [ -e "$SYSTEM_BIN/tlit-folio-touchpad" ]; then
  run sudo systemctl stop tlit-folio-touchpad.service 2>/dev/null || true
fi
system_changed=0
remove_if_same_root "$SYSTEM_BIN/tlit-folio-touchpad" \
  "$REPO_ROOT/scripts/tlit-folio-touchpad" "touchpad rescue helper"
remove_if_same_root "$UNIT_DIR/tlit-folio-touchpad.service" \
  "$REPO_ROOT/config/systemd/tlit-folio-touchpad.service" "touchpad rescue unit"
remove_if_same_root "$UDEV_DIR/99-tlit-folio-touchpad.rules" \
  "$REPO_ROOT/config/udev/99-tlit-folio-touchpad.rules" "touchpad rescue udev rule"
if [ "$system_changed" -eq 1 ]; then
  run sudo systemctl daemon-reload
  run sudo udevadm control --reload-rules
fi

# ------------------------------------------------ data files
LITE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/tablet-lite"
remove_if_same "$LITE_DATA/wvkbd-hide-key.patch" \
  "$REPO_ROOT/config/wvkbd/wvkbd-hide-key.patch" "wvkbd hide-key patch"
[ -d "$LITE_DATA" ] && run rmdir --ignore-fail-on-non-empty "$LITE_DATA"

# ------------------------------------------------ user-local wvkbd build
# A build artifact (not byte-comparable). Remove it only when it is the lite
# build: ▼ present, no full-plugin 手写/texp-ink-key hook.
VK="$BIN_DIR/wvkbd-deskintl"
if [ -x "$VK" ] && grep -q $'\xE2\x96\xBC' "$VK" 2>/dev/null \
    && ! grep -q 'texp-ink-key' "$VK" 2>/dev/null; then
  run rm -f "$VK"
  log "removed lite wvkbd build: $VK"
elif [ -e "$VK" ]; then
  warn "left $VK in place (not the lite build)"
fi

# ------------------------------------------------ summary
cat <<EOF

Done.

Kept on purpose:
  - ~/.config/voxtype/replacements.tsv (user data)
  - the voxtype service (still used by the F9 / SUPER+CTRL+X hotkeys)

Helpers are installed as tlit-*; the pre-1.5 texp-* copies are no longer used.
If this machine still carries them, delete them with the full plugin's installer.

The folio touchpad rescue (systemd unit + udev rule + /usr/local/bin helper) is
gone too. The keyboard keeps working, but detaching and re-attaching the folio
can leave the touchpad without tap / clickpad press / 2- and 3-finger gestures
until the next reboot.

Remove the plugin itself:
  omarchy plugin remove maxt.tablet-lite
  omarchy plugin remove maxt.mousehop
EOF

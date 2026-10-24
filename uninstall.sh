#!/usr/bin/env bash
# ============================================================================
# uninstall.sh — reverse everything install.sh did for Tablet Lite.
#
# Safety rules:
#   - files are removed only when they byte-match the repo copy (user edits are
#     kept and reported instead)
#   - packages are not auto-removed (they are shared; a reminder is printed)
#   - the user's voxtype replacement table is user data — left in place
#
# Usage:
#   ./uninstall.sh             undo install.sh changes
#   ./uninstall.sh --dry-run   preview only, change nothing
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HYPR_DIR="${HYPR_DIR:-$HOME/.config/hypr}"
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

[ "$DRY_RUN" -eq 1 ] && log "DRY RUN — nothing will be changed"

# ------------------------------------------------ hyprland hooks
for f in "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/autostart.lua"; do
  [ -f "$f" ] || continue
  if grep -qF 'require("hypr.tablet-lite")' "$f"; then
    run sed -i '\|require("hypr.tablet-lite")|d' "$f"
    log "removed from $f: require(\"hypr.tablet-lite\")"
  fi
done
remove_if_same "$HYPR_DIR/tablet-lite.lua" \
  "$REPO_ROOT/config/hypr/tablet-lite.lua" "hypr config"

# ------------------------------------------------ voxtype wiring
if command -v voxtype >/dev/null 2>&1; then
  if [ -x "$BIN_DIR/texp-voxtype-wire" ]; then
    VW_RC=0
    run "$BIN_DIR/texp-voxtype-wire" --uninstall || VW_RC=$?
    case $VW_RC in
      0) log "voxtype: removed the pre_output_command (mousehop release hook)" ;;
      1) log "voxtype: no pre_output_command hook to remove" ;;
      *) warn "voxtype pre_output_command not removed (exit $VW_RC) — check ~/.config/voxtype/config.toml" ;;
    esac
  fi
  cur="$(voxtype config get output.post_process.command 2>/dev/null | tr -d '"')"
  if [ "$cur" = "$BIN_DIR/texp-vtext" ]; then
    run voxtype config unset output.post_process.command
    log "voxtype: unset output.post_process.command (was $cur)"
  elif [ -n "$cur" ] && [ "$cur" != "null" ]; then
    warn "voxtype post_process.command is not ours ($cur) — left in place"
  fi
  run systemctl --user restart voxtype 2>/dev/null \
    || warn "could not restart voxtype via systemctl --user — run: systemctl --user restart voxtype"
fi

# ------------------------------------------------ helper scripts
for src in "$REPO_ROOT"/scripts/texp-*; do
  [ -f "$src" ] || continue
  remove_if_same "$BIN_DIR/$(basename "$src")" "$src" "helper script"
done

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
  - packages: squeekboard, wtype (shared system packages)
  - the voxtype service (still used by the F9 / SUPER+CTRL+X hotkeys)

Remove the plugin itself:
  omarchy plugin remove maxt.tablet-lite
EOF

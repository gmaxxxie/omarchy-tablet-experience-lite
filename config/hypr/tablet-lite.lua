-- Tablet Lite — generated configuration (installed by install.sh).
--
-- Only what the lite features need:
--   * SUPER+U toggles the on-screen keyboard (texp-vk; wvkbd-deskintl when the
--     lite build is present, squeekboard otherwise).
--   * SUPER+SHIFT+R asks the plugin for the next 90° rotation, so the angle is
--     persisted and sensor-following turns off.
--   * `above_lock 2` keeps wvkbd visible and interactive above the Omarchy
--     lock surface, so a keyboard raised for password entry is not hidden.
-- Laptop/tablet mode switching, touch gestures, handwriting and bar
-- decluttering are deliberately absent.
hl.layer_rule({
  match = { namespace = "wvkbd" },
  above_lock = 2,
})

hl.bind("SUPER + U", hl.dsp.exec_cmd("texp-vk toggle"), {
  description = "Toggle virtual keyboard (wvkbd)",
})

-- Rotation belongs to the plugin (not a bare `texp-rotate next`) so the
-- service can persist the angle, turn sensor-following off, and keep the
-- bar icon/tooltip in sync.
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("omarchy-shell maxt.tablet-lite rotationNext"), {
  description = "Rotate screen: next 90° (tablet lite)",
})

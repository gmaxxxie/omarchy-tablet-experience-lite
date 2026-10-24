-- Tablet Lite — generated configuration (installed by install.sh).
--
-- Only what the two lite features need:
--   * SUPER+U toggles the on-screen keyboard (texp-vk; wvkbd-deskintl when the
--     lite build is present, squeekboard otherwise).
--   * `above_lock 2` keeps wvkbd visible and interactive above the Omarchy
--     lock surface, so a keyboard raised for password entry is not hidden.
-- Rotation, mode switching, touch gestures, handwriting and bar decluttering
-- are deliberately absent — this is the voice + keyboard subset.
hl.layer_rule({
  match = { namespace = "wvkbd" },
  above_lock = 2,
})

hl.bind("SUPER + U", hl.dsp.exec_cmd("texp-vk toggle"), {
  description = "Toggle virtual keyboard (wvkbd)",
})

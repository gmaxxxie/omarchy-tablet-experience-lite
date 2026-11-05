-- mousehop KVM — is the pointer/keyboard armed to cross to the peer machine?
--
-- Installed by install.sh from config/hypr/mousehop.lua; required from
-- ~/.config/hypr/hyprland.lua. Kept apart from tablet-lite.lua because the KVM
-- switch is not a tablet feature: either file can be removed alone.
--
-- The bar widget maxt.mousehop (installed by the same script) shows the state
-- and toggles it; keep the two in step — both call tlit-mousehop-toggle.
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("tlit-mousehop-toggle toggle"), {
  description = "KVM: mousehop on/off",
})

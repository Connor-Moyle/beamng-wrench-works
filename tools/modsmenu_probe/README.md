# Mods menu probe (test only)

Checks that a mod can add a tab and a button to the ESC (pause) menu in 0.39 before the real Mods menu is built.

1. `powershell -File tools\modsmenu_probe\install.ps1` (copies the mod into the BeamNG user folder, unpacked). Restart the game once.
2. Freeroam: load any level, press ESC. Look for a tab "SLRR probe" with a button "Probe card", and a "SLRR probe (shared Mods tab)" button under Mods. Open the card: it should show a heading and a button that counts clicks. Screenshot.
3. Career (Street Legal): the same.
4. If nothing shows: Lua console, `slrrMenuProbe.status()` shows what the game answered; `slrrMenuProbe.register()` tries again. Send the answer text and the log lines mentioning `uiMods` or `ui_pause_actions`.
5. Delete `mods\unpacked\slrr_menu_probe` afterwards.

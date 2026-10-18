-- Wrench Works: load the extension and keep it alive across level loads.
extensions.load('slrr_garage')
setExtensionUnloadMode('slrr_garage', 'manual')
extensions.load('slrr_carRadio')
setExtensionUnloadMode('slrr_carRadio', 'manual')
-- the Mods menu's settings registry (pause menu > Mods menu); other mods register their settings with it when it is loaded (soft: they check slrr_settings)
extensions.load('slrr_settings')
setExtensionUnloadMode('slrr_settings', 'manual')

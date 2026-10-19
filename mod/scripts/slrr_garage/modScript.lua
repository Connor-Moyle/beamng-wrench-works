-- Wrench Works: load the extension and keep it alive across level loads.
setExtensionUnloadMode('slrr_garage', 'manual')
extensions.load('slrr_garage')
setExtensionUnloadMode('slrr_carRadio', 'manual')
extensions.load('slrr_carRadio')
-- the Mods menu's settings registry (pause menu > Mods menu); other mods register their settings with it when it is loaded (soft: they check slrr_settings)
setExtensionUnloadMode('slrr_settings', 'manual')
extensions.load('slrr_settings')

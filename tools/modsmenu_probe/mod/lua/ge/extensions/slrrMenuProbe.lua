-- Test only: registers a pause-menu tab "SLRR probe" with one button that opens Probe.vue. Registers at load and at every level start; slrrMenuProbe.status() says what the game answered.
local M = {}
local answers = {}
local function register()
  local a = rawget(_G, 'ui_pause_actions')
  if not a then pcall(extensions.load, 'ui_pause_actions') a = rawget(_G, 'ui_pause_actions') end
  if not a then answers = { 'ui_pause_actions is not loaded' } return end
  answers = {
    dumps(a.registerModTab({ id = 'slrr_probe', label = 'SLRR probe', icon = 'wrench' })),
    dumps(a.registerModButton({ id = 'slrr_probe_one', tabId = 'slrr_probe', label = 'Probe card', icon = 'wrench', componentName = '/ui/ui-vue/mods/slrr_menu_probe/Probe.vue' })),
    dumps(a.registerModButton({ id = 'slrr_probe_shared', tabId = 'mods', label = 'SLRR probe (shared Mods tab)', icon = 'wrench', componentName = '/ui/ui-vue/mods/slrr_menu_probe/Probe.vue' })),
  }
end
M.register = register
M.status = function() return table.concat(answers, ' | ') end
M.onExtensionLoaded = register
M.onClientStartMission = register
return M

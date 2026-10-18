// The Mods menu pages talk to the slrr_settings Lua extension through the engine's Lua bridge.
// `lua.extensions.<name>` only exists for the extensions in the game's own signature table, so our own extension is called by name here.
import { useBridge } from "@/bridge"

export function call(fn, ...args) {
  const { api } = useBridge()
  const code = `extensions.slrr_settings.${fn}(${args.map(a => api.serializeToLua(a)).join(",")})`
  return new Promise(resolve => api.engineLua(code, resolve))
}

// The pause menu gives a mod page a narrow card: open the page as a screen of its own (route menu.slrrMods, like Options). page: mod | find | quick
export function openFull(page, mod, tab) {
  const { api } = useBridge()
  const arg = api.serializeToLua({ page, mod: mod || "", tab: tab || "" })
  api.engineLua(`extensions.ui_router.navigate('menu.slrrMods', ${arg})`)
}

// The Mods menu pages talk to the slrr_settings Lua extension through the engine's Lua bridge.
// `lua.extensions.<name>` only exists for the extensions in the game's own signature table, so our own extension is called by name here.
import { useBridge } from "@/bridge"

export function call(fn, ...args) {
  const { api } = useBridge()
  const code = `extensions.slrr_settings.${fn}(${args.map(a => api.serializeToLua(a)).join(",")})`
  // a call the game never answers (the extension is gone, the Lua errored) rejects after 8 s, so a page shows an error instead of hanging
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`no answer from ${fn}`)), 8000)
    api.engineLua(code, r => { clearTimeout(timer); resolve(r) })
  })
}

// The pause menu gives a mod page a narrow card: open the page as a screen of its own (route menu.slrrMods, like Options). page: mod | find | quick
export function openFull(page, mod, tab) {
  const { api } = useBridge()
  const arg = api.serializeToLua({ page, mod: mod || "", tab: tab || "" })
  api.engineLua(`extensions.ui_router.navigate('menu.slrrMods', ${arg})`)
}

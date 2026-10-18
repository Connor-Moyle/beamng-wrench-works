// The Mods menu pages talk to the slrr_settings Lua extension through the engine's Lua bridge.
// `lua.extensions.<name>` only exists for the extensions in the game's own signature table, so our own extension is called by name here.
import { useBridge } from "@/bridge"

export function call(fn, ...args) {
  const { api } = useBridge()
  const code = `extensions.slrr_settings.${fn}(${args.map(a => api.serializeToLua(a)).join(",")})`
  return new Promise(resolve => api.engineLua(code, resolve))
}

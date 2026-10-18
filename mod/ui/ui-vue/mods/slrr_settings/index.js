// Registers the Mods menu pages as a screen (route menu.slrrMods) next to the pause-menu cards, so a page can be opened by name (the in-game check does this).
import { useBridge } from "@/bridge"
import RouteHost from "./RouteHost.vue"

const { lua } = useBridge()
const sourceId = "slrr-settings.routes"
const routes = [
  {
    path: "/slrr-mods/:page/:mod?/:tab?",
    name: "menu.slrrMods",
    component: RouteHost,
    meta: { luaRoute: { title: "Mods menu", backTarget: "menu" } },
  },
]

export async function onLoad() {
  window.bngRoutes.add([{ path: sourceId, routes }])
  const result = await lua.extensions.ui_router_routeManager.registerModRoutes(
    sourceId,
    routes.map(r => ({ name: r.name, path: r.path, meta: r.meta })),
  )
  if (!result?.success) {
    window.bngRoutes.remove([sourceId])
    console.error("Mods menu: the route was not registered", result?.errors)
  }
}

export async function onUnload() {
  window.bngRoutes.remove([sourceId])
  await lua.extensions.ui_router_routeManager.unregisterModRoutes(sourceId, { fallbackRoute: "menu" })
}

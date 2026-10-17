# The Mods menu (ESC > Mods): one settings schema for all our mods

Status: DESIGN (branch `mods-menu`), not built. Written by connor-9e for connor-62, ba, a5, 82, 0f.

## How it gets into the game (no game file is replaced)

BeamNG 0.39 has a Vue UI with a mod mechanism (`<game>/ui/ui-vue/mods/README.md`):

- Vue single-file components in a mod's `ui/ui-vue/mods/<name>/` folder are discovered by `lua/ge/extensions/ui/uiMods.lua` and compiled at run time.
- `lua.extensions.ui_pause_actions.registerModTab({ id, label, icon })` and `registerModButton({ id, tabId, label, icon, componentName, props })` put a tab and buttons into the ESC (pause) menu. A button's `componentName` is a path to our `.vue` file; the game mounts it as the card.
- Both calls can be made from a GE Lua extension, so the menu entry is registered by Lua at start-up, no JavaScript entry point is needed. Registering again with the same id replaces it, and `unregister*` removes it.

So: **the Mods menu lives in the Wrench Works mod** (every other mod of ours needs it or sits beside it): a Lua registry `slrr_settings` (ge/extensions/slrr/settings.lua, loaded by Wrench Works' modScript) and `ui/ui-vue/mods/slrr_settings/ModsMenu.vue`. The registry registers one pause tab `slrr` with one button per mod (Wrench Works, Street Legal, Pedestrians & Drivers, Car Surface FX, Valo City ...). Each button opens that mod's page: its tabs along the top, the tab's fields below. A mod that is not installed has no button. A mod that runs without Wrench Works (Car Surface FX alone) keeps its Options-page group and simply skips registering (`if slrr_settings then`).

Open point for the game test: does a mod-registered button in a pause *tab* of ours show on a career/freeroam pause menu, on the 0.39 build we have? (README says the shared "mods" tab only appears while it has buttons.) The fallback is the shared `mods` tab, which the registry also supports (`tabId = 'mods'`).

## The schema

A mod registers once, at extension load, and again whenever `onSlrrSettingsReady` fires (the registry sends that hook after it loads, so load order does not matter):

```lua
function M.onSlrrSettingsReady() if slrr_settings then slrr_settings.register(M.schema()) end end
M.onExtensionLoaded = M.onSlrrSettingsReady      -- (does nothing if the registry is not loaded yet)
```

```lua
slrr_settings.register({
  mod = 'car_surface_fx',                 -- unique id, a-z 0-9 _
  title = 'Car Surface FX',
  icon = 'wrench',                        -- a game icon id
  order = 40,                             -- the sort of the mods in the menu
  tabs = {
    { id = 'rain', title = 'Rain & glass', description = 'One or two plain lines about the tab.' },
    { id = 'dirt', title = 'Dirt & wear' },
  },
  fields = {
    { id = 'rain', tab = 'rain', group = 'Paint', type = 'bool', label = 'Wet paint and water beads', tooltip = 'Two plain sentences.',
      default = true, store = { kind = 'setting', key = 'csfxRain' }, apply = 'live' },
    ...
  },
})
```

### Common field keys

| key | meaning |
|---|---|
| `id` | unique inside the mod |
| `tab` | a tab id of the mod |
| `group` | optional heading inside the tab; fields with the same group sit together, in the order given |
| `type` | one of the types below |
| `label`, `tooltip` | plain words; the tooltip is 1 to 2 sentences, no jargon, says what turning it down or off does |
| `default` | the start value (what the tab's "Reset to defaults" restores) |
| `store` | where the value lives (see below) |
| `apply` | `'live'` (default: takes effect at once), `'spawn'` (cars spawned afterwards), `'restart'` (after a game restart), shown as a small tag in the menu |
| `onChange` | optional `function(value)` called after the value was written, for mods that need to push it into running code |
| `visibleIf` | optional `{ field = 'otherId', equals = true }`: shown only while that field has that value |
| `advanced` | true: shown only when the menu's "Show advanced" switch is on (for the many tunables) |

### Types

| `type` | extra keys | value | menu control |
|---|---|---|---|
| `heading` | `label` | none | a subheading; no store |
| `note` | `label` | none | a read-only paragraph (known limits, a hint) |
| `bool` | | boolean | switch |
| `slider` | `min`, `max`, `step`, `unit` (`'%'`, `'m'`, `'s'`, `'x'`, `''`), `scale` (multiplier shown to the player, default 1) | number | slider with a number box |
| `int` | `min`, `max` | integer | stepper |
| `enum` | `options = { { id = 'a', label = 'A' }, ... }` | the option id | dropdown (or pills when 3 or fewer) |
| `color` | `alpha` (bool) | `{ r, g, b[, a] }`, 0..1 | colour picker with swatch |
| `texture` | `folder` (a game path), `exts = { 'png', 'jpg', 'dds' }`, `none = true` (allow "none"), `thumbs = true` | the chosen file's path (`'/art/..../x.png'`), or `''` | a tile grid of the files of the folder with thumbnails; the list is read by the registry (`FS:findFiles`) when the page opens, so a file added later shows at the next open |
| `button` | `action = function()` or `action = 'ext.function'` | none | a button; the result text it returns (a string) is shown as a toast |
| `text` | `maxLength` | string | text box |

### Where a value lives (`store`)

A field names where its value is read and written, so a mod does not write get/set pairs:

- `{ kind = 'setting', key = 'csfxRain' }`: one of the game's settings (`settings.getValue/setValue`), the same keys the Options page uses today. Existing values stay where they are, nothing to migrate; the Options-page group and the Mods menu show the same value.
- `{ kind = 'json', file = '/settings/carSurfaceFx.json', path = 'windscreen.intensity' }`: a path inside a json file in the user folder (dots for the keys). The registry reads and writes the key and keeps the rest of the file; it writes only when a value changed.
- `{ kind = 'custom', get = function() return v end, set = function(v) end }`: anything else (a value inside the career save, a module table).

`default` is used by Reset and for a value that is not stored yet. Registration never writes anything.

### Reset

Each tab has "Reset to defaults": it writes the `default` of every field of that tab (not the headings, notes or buttons) through the same store and calls `onChange`. The menu asks to press twice (a confirm line), so a stray click does not wipe a tab.

## What the registry offers the Vue page (the page only talks to these)

```
slrr_settings.mods()                         -> { { mod, title, icon, tabs = { {id,title,description} } } }   (installed mods that registered)
slrr_settings.page(mod, tab)                 -> { fields = { ...schema fields with `value` filled in, `files` for texture fields } }
slrr_settings.set(mod, field, value)         -> { ok, value, error }     (validates type and range, clamps, stores, applies, calls onChange)
slrr_settings.reset(mod, tab)                -> the page again
slrr_settings.press(mod, field)              -> { ok, text }
```

Values from the page are always validated and clamped by the registry (never trusted): a number outside min/max is clamped, an enum value not in `options` is refused, a texture path must be a file the folder listing contains.

## Accessibility and layout rules the page keeps

- Everything reachable with keyboard and pad: tabs on the bumpers or left/right, fields on up/down, a switch on A/Enter, a slider on left/right (step) or a held stick, Back (B/Esc) goes up one level. Every control is a `bng-nav-item`.
- Contrast at WCAG AA against the card background; state never by colour alone (switch shows On/Off text; the changed-from-default mark is a dot and the words "changed").
- The layout is a column of rows that wraps and scrolls inside the card; checked at 1920x1080 and 3440x1440 (the card keeps a readable line length, it does not stretch across the ultrawide).
- Text size follows the game's UI scale and our Text size setting (slScale).

## What each mod does

1. Put its tunables in `fields` (hard-coded constants worth changing, with a sane `min/max`; the rest stays out). Mark expert ones `advanced = true`.
2. Keep reading its values the way it does now (settings keys, json) so nothing else changes.
3. Register in `onSlrrSettingsReady` (and at extension load).
4. Provide a `description` per tab and a `tooltip` per field in plain words.

Car Surface FX (ba): the existing Options group becomes the first tabs (Rain & glass, Dirt & wear, Weather extras); the ported Surface FX modules get Skid marks & terrain, Leaks & debris, Textures (`texture` fields for the folders of decals).

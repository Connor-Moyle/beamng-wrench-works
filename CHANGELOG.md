# Changelog: BeamNG Wrench Works (garage)

## 1.8.2

Works with BeamNG 0.40.

- **Fixed:** long drop-down lists in the Mods menu didn't save your choice (the lists with seven or more entries, such as the anti-aliasing mode).
- **New:** BeamNG 0.40 upscaling on the Graphics page, with quality and sharpness, set through the game's own settings. DLSS is tested; FSR and XeSS are listed when your card supports them but are not tested yet.
- The details of the upscaling: the Anti-aliasing & sharpening page has an **Upscaling** group: Upscaler (only what your card supports: DLSS, FSR 3/4, XeSS, FSR custom, PSSR, SMAA T2x, SMAA, FXAA, Off), Quality (DLAA / Quality / Balanced / Performance / Ultra Performance), Render scale (Advanced) and Sharpness, all through the game's own settings, so Options > Graphics stays in sync. While a temporal upscaler is on, our FXAA HQ / SMAA Ultra / Temporal smoothing / shimmer reduction are switched off and greyed out, and our sharpener runs only as CAS with Sharpness 0. The "not available in mods" list now holds Frame Generation and Reflex (not in 0.40's Lua), FSR 1 and NIS upscaling, MSAA and supersampling beyond the screen. *(Built and tested offline; not yet seen in the game.)*
- The Mods menu can grey a row out and say why (`disabledIf`).
- The extension unload mode is set before each extension is loaded, so 0.40 does not warn.

## 1.8.1

Mods menu layout fixes, seen in the game by the tester (screenshots of every tab):
- The help panel starts below the career HUD, has a title (the setting name) and an orange frame, and its text has its own scroll (a long help overflowed by 25 px and scrolled to its last line when set through the page; scrolling with a real wheel not yet tried by a person).
- Rows are about as wide as in Options, sliders sit beside their labels, one row height (a toggle a little shorter), groups are dark cards.
- The page title is no longer hidden behind the HUD clock; the reset button is clear of the pause button; the background lets the game show faintly through.

## 1.8.0

What is new since 1.7.0, for players.

### Built, not yet tested in game
Built, with offline tests, but not yet seen working in the game. An item leaves this list only when the tester posts a pass.
- **The Mods menu (ESC > Mods menu)** with the settings registry other mods use; Wrench Works' own settings are on it (money, delivery, garage, radio, catalog). The garage screen no longer has a Settings panel (the values are the same).
- **Mods menu like Options:** each row is a title and a control on one line, the help text shows in a side panel (hover or keyboard/controller focus), tabs whose settings are all advanced show them, a note shows its text, the reset button is no longer under the career HUD, and the money button (Developer tab) asks for a second click. The side panel and the new row layout are not yet seen in the game; the earlier layout was seen working in a real-click pass: every tab of every mod changed one setting, stuck after reopening and restored exactly, the puddle count, Search and Quick setup presets too.
- **Graphics and camera on the Mods menu:** anti-aliasing, sharpening, Look and the cinematic camera (the Options > Graphics groups are removed).
- **Latch logging:** a door or boot latch that breaks is logged with its force and speed (to find why the pessima's rear latches break).

### Graphics

- **Look** (a tab of the Mods menu page "Wrench Works: graphics & camera", off by default): a light colour grade and vignette on the finished picture; presets Natural, Cinematic, Vivid, or your own Contrast, Saturation, Warmth, Colour split and Vignette. Off puts the game's picture back exactly. *(Built, not yet tested in game.)*
- **Cinematic camera** (a third tab of that page, off by default): for replays and photos. Motion blur strength and depth of field (the game's own effects, focus follows the car), and letterbox bars (2.39:1, 2:1, 1.85:1, top and bottom; none on a screen already that wide); presets Subtle, Film, Dramatic. Turning it off puts the game's own blur and depth of field back exactly; it keeps out of the way while photo mode is open. *(Built, not yet tested in game.)*
- **Anti-aliasing choices** (in the pause-menu Mods menu, ESC > Mods > Wrench Works: graphics & camera, "Game's own" by default, live, with a note under each): Off, FXAA, FXAA HQ, SMAA High, SMAA Ultra (own shader copies, colour edges, optional depth predication) and SMAA Ultra + Temporal smoothing (a blend with the previous frame through the game's motion vectors; calms shimmer, adds no detail). Switching back to "Game's own" restores the game's state exactly.
- **Sharpening** (off by default): AMD CAS, AMD FSR 1 RCAS or NVIDIA NIS sharpen, with a strength slider.
- **Temporal smoothing** now backs off on foliage, fences and wires (depth steps around the pixel, history from another surface, colour clamp) and there is an optional edge smoothing pass (the game's own, off by default). *(Built, not yet tested in game.)*
- **Specular shimmer reduction** slider (off by default) for sparkle on car paint and wet roads. *(Built, not yet tested in game.)*
- **Presets:** Balanced, Smooth, Maximum. The settings also list what a mod cannot do (DLSS, DLAA, FSR 2/3/4, TAA, real supersampling) and why.

### Garage and cars

- **Car Surface FX** (optional mod): the car's info shows its **Dirt** and **Scratches** when the mod is installed, and a paint job or a repair in a Street Legal career cleans the paint and buffs the scratches out.
- The garage screen stays smoother while you work: the part previews are measured every second frame instead of every frame.
- **Recorded damage** is kept more faithfully on a respawn: only plain beams are re-measured or broken, and the nodes next to special beams, wheels and fixed nodes are left alone.

### Names

- The arrival-scene setting and the README's music example use the player-facing names (Wrench Works: Drivers & Pedestrians, Street Legal Racing Redline).

## 1.7.0

What is new since 1.6.0, for players.

### Garage

- **The garage is yours the moment the car stops.** After you park, the driver gets out, walks round the car looking it over and shuts the door while you already work: the screen is up and everything is usable, the scene only plays in the background. If it cannot play, the garage still opens.
- **Leaving, whatever car is on the lift.** Next to **Drive out** (career) there are **Store this car** (the car is put away and you stay on foot; bring it or another car out from the phone) and **Walk out** (leave on foot, the car waits in the garage).
- **Upgrades (career).** The garage bar has an **Upgrades** panel: lift, engine crane, workbench, dyno, paint booth, more shelves and a photo corner, bought for this garage. A new garage starts bare and the lift and the crane only stand in it once you own them.
- **The right tool for the job.** Engine work (taking an engine out or fitting one) needs the **engine crane**; the underside (gearbox, suspension, driveline, headers) needs the **lift**. A crude animation shows the engine rising out of the bay on the crane and going back in.
- **Tabs.** Services is car servicing only; Races and Drivers are tabs of their own.
- **Engine swaps in a career** cost labour when an engine goes into an occupied engine slot (the old engine goes on the shelf); the shelf engine shows a quote.
- **Doors.** Entering by stopping on the marker works whichever way the car faces; on foot the doorway is a generous zone (as wide as the garage, any direction) and in a career takes you in with your current car. A garage can be closed by the career (no marker, and the reason is shown once at the door).
- **Garage on a gamepad.** The right stick orbits, the zoom buttons zoom, centre-camera resets, B closes a panel, and tooltips show on focus.
- **Shop opening hours** in a Street Legal career (08:00-18:00; the counters are shut in the night phase).

### Catalog and shops

- **Search stays in the chapter you are in.** With Running gear > Rear wheels open, the search box only looks through rear wheels; an **All chapters** switch widens it.
- **Wheel size buttons.** Wheel chapters show size (and width) buttons taken from the parts' own data, so picking 15" shows only 15" rims.
- **Fit them here.** At a parts shop (not the used-parts yard) you can buy and fit on the car you drove in: the parts are fitted at the counter for a labour charge (12 % of the part price, at least $8 each) and the car is rebuilt on the spot.
- **What a part does.** Hover a part in the catalog: an engine shows peak power and torque with the rpm, its rev range and what it is rated for; a turbo its boost; springs, brakes and tyres their grip, torque and weight.
- **Under $1,500** filter for cheap upgrades.

### Tuning, paint and photos

- **Tune panel.** The Tune icon opens a panel on the right with every tuning item of the car, all or one category, grouped as the game's own tuning menu groups them. The dyno draws your first (or pinned) run dashed under each new one and shows the gain at the peaks.
- **Paint finishes.** Gloss, satin, matte, metallic, pearl and chrome keep the colour you are mixing; **All three** sprays one paint on every colour slot.
- **Photos.** **Photo** hides the screen and saves a picture of the car (screenshots/slrr_garage); **Showcase** turns the camera slowly round it; **Photo mode** opens the game's own.
- **Driver outfits.** In the Drivers tab: six shirt-and-trousers outfits and a helmet switch, shown where the driver has a helmet model.

### Other

- **Car radio while you drive.** The garage radio's music plays in the car too: a station per music folder (loose tracks are "Wrench Works FM"), keys for on/off and next station, and each car remembers its station.
- **More settings.** A Driver group (who sits in the car, shirt, trousers, size, helmet, how it moves), Injuries, and a World group for the pedestrians, shown when Drivers & Pedestrians is installed.
- **Job cars.** A part taken off a customer's car sells for nothing and can only go back onto a job car.
- **All the garage's words live in one table** (`slrr/garageStrings.lua`, with the screen's own fallbacks), ready for reading or translating.

### Fixes

- Doors and lids that stayed open after a visit are fixed: a kept dent no longer breaks a latch for good, the latches are pushed shut when the car comes out and again when it has stopped outside, and the retries wait while the car is frozen.
- A part is never lost on its way to the shelf: nothing is taken off a car unless the shelf takes it.
- Dents survive a rebuild: parts that fell off on the road are listed with the damage, and dents put back on a car use only safe panel beams.
- Entering no longer hangs when the arrival scene fails, and some screen errors on the garage's first frame are gone.
- Cancelling a garage visit no longer pulls you back into the garage car.

### For other mods

- A career can set what the garage has (lift, crane, workbench, dyno, paint booth, photo corner, shelf size) and is told about the shelf, repairs, dyno sheet, part sales and drive-out; it can close a garage and add entries to the Services, Races and Drivers tabs.
- `slrr_garage.settingsDefs()` lists every setting (other mods' groups too); `enterWith(vehicleId, mode)` and `garageAt(pos)` open the garage on a car; `slrrGarageVeh.apply(data, { done = 'lua', keepLatches = true })` puts damage back and says when it is on.

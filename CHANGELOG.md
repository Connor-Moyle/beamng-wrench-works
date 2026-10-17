# Changelog: BeamNG Wrench Works (garage)

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

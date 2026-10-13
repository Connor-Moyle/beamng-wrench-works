# Garage mod for BeamNG.drive

A working garage for BeamNG.drive, built to feel like the one in *Street Legal Racing: Redline*. Roll up to a garage on West Coast USA, watch the car drive itself in onto the lift, then work on it by hand: click parts off, click them back on, tune, paint, repair, order new parts from the catalog, and drive out the other door.

![The garage](docs/screenshots/02_garage.jpg)

It is a tribute to how that game's garage plays. Nothing from Street Legal Racing: Redline is used or included: all code here is written for BeamNG, and all models and textures come from BeamNG itself.

Built on BeamNG.drive 0.39.4.

## Getting it running

1. Download `slrr_garage.zip` from the Releases page.
2. Drop it into your BeamNG mods folder (`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).
3. Load West Coast USA and drive into a garage doorway (orange marker) at walking pace. Faster than 15 km/h and you simply drive through; the limit is in Settings.

| Garage | Doors |
| --- | --- |
| Belasco City Garage (service station) | main door and side door: in by one, out by the other |
| Alder Dragway Garage | drive-through, either direction |
| Industrial Garage | drive-through hall, either direction |

The mod ships without sounds and is simply quiet. `tools/install.ps1` can copy a set of interface sounds from a Street Legal Racing: Redline install you own, if you want them.

## In the garage

| Do this | To get this |
| --- | --- |
| Click a part on the car | It comes off and lands on the shelf at the bottom, with everything bolted to it |
| Click a part on the shelf | It goes back on. If something is already in that slot, the two swap |
| Click the "+3 parts" tag on a shelf part | A list of what is bolted to it |
| Right-drag | Orbit the camera |
| Mouse wheel | Zoom |
| Middle-click a part | Look at that part |

Every part comes off except the body shell itself. Take off what you like and drive out without it.

The icon bar along the top:

- **Drive out** – builds the car as you left it and drives it out of the other door.
- **Catalog** – every part that fits the car, in five sections (Engine, Body, Running Gear, Interior, Paint) split into small chapters such as Front Bumpers, Rear Suspension or Front Tyres, with a search box per chapter. Parts go on a shopping list; you pay when you confirm it, and they are delivered to the shelf (see below).
- **Car info** – specs, part count and value, damage and repair cost.
- **Mechanic (wrench)** – the default mode: fit and remove parts.
- **Tune (screwdriver)** – click a door, hood or boot to open it; click any other part and it is outlined and a small panel pops up with just that part's adjustments (tyre pressure for a tyre, camber for the suspension, and so on). The full list is in the drawer on the right. Adjustments take effect when you drive out.
- **Lift** – every garage has a two-post lift. The car parks between its posts, the arms swing in under the sills, and this button carries the car about 1.3 m up, camera and all.
- **Paint booth** – factory colours or mix your own, three colour slots. The car disappears in a cloud of the new colour while it is sprayed.
- **Test engine**, **Advance time**, **Whole car** (camera reset) and **Settings**.

The mechanic's buttons sit left of the shelf: **Repair part**, **Repair car**, **Sell part**, **Sell everything** (asks first), and four toggles that hide the engine, body, running gear or interior so you can reach what is behind them.

## Ordering parts, delivery and shops

- **Shopping list.** "Add" in the catalog puts a part on the list. Nothing is paid until you press Confirm purchase.
- **Delivery.** Parts ordered from the garage are delivered, and delivery is charged by weight and bulk: a hood costs many times what a mirror or a hub cap does. Standard delivery takes a few minutes; express costs more and arrives ten times sooner. Arrivals drop onto the shelf while you are in the garage, or are waiting there next time.
- **Shops in town.** Six businesses on West Coast USA sell parts over the counter. Stop on the blue marker on their forecourt. You take the parts with you (they are on the shelf when you reach the garage), there is no delivery charge, and prices are 5% lower.

| Shop | Sells |
| --- | --- |
| Torres Tires | wheels, tyres, hubs |
| Belasco City Exhaust | exhausts and intakes |
| Fast Automotive | engines, turbos, nitrous, gearboxes, cooling, differentials |
| Smash Auto Repairs | body panels, lights, glass, spoilers, body kits |
| Jerry Riggs | suspension, brakes, steering, chassis bracing |
| Belasco Auto | interiors, trim, paint designs, accessories |

Delivery times (standard and express), delivery charges, the express surcharge and the shop discount can all be changed under Delivery in Settings.

![The lift](docs/screenshots/03_lift.jpg)

## Part previews

The parts in the catalog and on the shelf are the real 3D models, with the game's own textures, your paint and your livery, turning at the game's frame rate. They are held in front of the camera, so on the shelf they step aside while the camera is moving and come back when it rests.

## Damage and money

- Parts keep their damage. Take a bent bumper off and it is still bent when you refit it, and the car leaves as damaged as it arrived, visit after visit, unless you pay to repair it.
- In career mode the garage spends and earns your career money. Outside it you have a wallet of your own that goes down when you buy and up when you sell, and is remembered between sessions. Settings has the starting amount and an unlimited-money switch.
- Prices, sell-back value, repair cost, the budget, camera direction, preview speed and direction and a few other things are in the Settings screen.

## Why working on the car does not stutter

Changing a part in BeamNG normally rebuilds the whole vehicle, which freezes the game for about a second. Here the car is not rebuilt while you work:

- taking a part off or refitting it only switches its meshes off and on;
- a part the car was not built with, such as one you just bought, is shown as its model placed on the car where it belongs;
- tuning changes are just noted;
- the one real rebuild happens when you drive out, behind the fade. Repairs are the exception: they rebuild the car on the spot.

## Good to know

- The shelf (per car model), parts on order and your freeroam money are saved in `settings/slrr_garage/save.json` in your BeamNG user folder. "Keep parts and money between sessions" in Settings switches that off, so each time you start the game you begin from scratch.
- Two actions can be bound under Options > Controls > Gameplay: enter the nearest garage, and drive out. Handy when the car cannot drive itself to the door.
- Career mode: only money is wired up. The garage does not know about career's own parts inventory.
- More garages and shops can be added in `lua/ge/extensions/slrr/garageSites.lua` (a garage needs its parking spot, direction, door and wall distances and the way out; a shop needs a position and the catalog chapters it sells).
- `docs/beamng_post.txt` is the forum post for the mod, in BBCode.

## Source layout

| File | Job |
| --- | --- |
| `lua/ge/extensions/slrr/garage.lua` | state machine: door triggers, drive-in, garage, catalog, drive out, shop visits |
| `lua/ge/extensions/slrr/garageParts.lua` | parts tree, shelf, catalog, shopping list and deliveries, money, stand-in parts |
| `lua/ge/extensions/slrr/garagePicker.lua` | finds the part under the cursor |
| `lua/ge/extensions/slrr/garageCamera.lua` | drive-in, orbit and drive-out camera |
| `lua/ge/extensions/slrr/garageDamage.lua`, `lua/vehicle/extensions/slrrGarageVeh.lua` | damage that survives rebuilding the car, the lift |
| `lua/ge/extensions/slrr/garageShapes.lua` | cuts single parts out of the vehicle's model files |
| `lua/ge/extensions/slrr/garagePreview.lua` | shows those parts: turning previews and parts placed on the car |
| `lua/ge/extensions/slrr/garageLift.lua` | the car lift: its model and its movement |
| `lua/ge/extensions/slrr/garageSites.lua` | the garages and shops and where they are |
| `lua/ge/extensions/slrr/garageCatalog.lua`, `garageSettings.lua` | catalog chapters, settings |
| `ui/modules/apps/slrrGarage/app.js` | the garage screen |

Not affiliated with BeamNG GmbH or the makers of Street Legal Racing: Redline.

# SLRR Garage for BeamNG.drive

The garage from *Street Legal Racing: Redline*, rebuilt inside BeamNG.drive. Roll up to the Belasco City Garage on West Coast USA, watch the car drive itself in, then work on it the SLRR way: click parts off, click them back on, tune, paint, repair, order new parts from the catalog, and drive out.

Built on BeamNG.drive 0.39.4.

## Getting it running

1. Download `slrr_garage.zip` from the Releases page.
2. Drop it into your BeamNG mods folder (`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).
3. Load West Coast USA and drive at the orange marker in front of the Belasco City Garage door.

Sounds are optional. If you own Street Legal Racing: Redline, run `tools/install.ps1` from a clone of this repo and it copies the garage sounds over from your own install (they are not included here). Without them the garage is simply silent.

## In the garage

| Do this | To get this |
| --- | --- |
| Click a part on the car | It comes off and lands on the shelf at the bottom, with everything bolted to it |
| Click a part on the shelf | It goes back on. If something is already in that slot, the two swap |
| Right-drag | Orbit the camera |
| Mouse wheel | Zoom |
| Middle-click a part | Look at that part |

The icon bar along the top is SLRR's garage menu:

- **Drive out** – builds the car as you left it and puts you back on the street. You can leave with parts missing, wheels included.
- **Catalog** – every part that fits the car, in five sections (Engine, Body, Running Gear, Interior, Paint) split into small chapters such as Front Bumpers, Rear Suspension or Front Tyres, with a search box per chapter. Each part is shown as a white 3D model turning on the spot. Whatever you buy lands on the shelf.
- **Car info** – specs, part count and value, damage and repair cost.
- **Mechanic (wrench)** – the default mode: fit and remove parts.
- **Tune (screwdriver)** – click a door, hood or boot to open it; click any other part and it is outlined and a small panel pops up with just that part's adjustments (tyre pressure for a tyre, camber for the suspension, and so on). The full list is in the drawer on the right.
- **Lift** – raises the car about 1.3 m so you can get the camera underneath it. Press again to lower it.
- **Paint booth** – factory colours or mix your own, three colour slots.
- **Test engine**, **Advance time**, **Whole car** (camera reset) and **Settings**.

The mechanic's buttons sit left of the shelf: **Repair part**, **Repair car**, **Sell part**, and four toggles that hide the engine, body, running gear or interior so you can reach what is behind them.

## Damage and money

- Parts keep their damage. Take a bent bumper off and it is still bent when you refit it, and the car leaves as damaged as it arrived unless you pay to repair it.
- In career mode the garage spends and earns your career money. Everywhere else you get a fixed budget that never runs down.
- Prices, sell-back value, repair cost, the budget and a few other things are in the Settings screen. There is also an option to swap the white preview models for photographs of the real parts, livery included; it makes entering the garage slower, so it is off unless you want it.

## Why swapping parts does not stutter

Changing a part in BeamNG normally rebuilds the whole vehicle, which freezes the game for about a second. Here nothing is rebuilt while you work:

- taking a part off or refitting it only switches its meshes off and on;
- parts you buy are loaded once, behind the fade when the catalog closes, and kept hidden on the car until you fit them;
- the one real rebuild happens when you drive out, behind the fade to the street.

## Good to know

- The shelf is saved per car model in `settings/slrr_garage/save.json` in your BeamNG user folder.
- Two actions can be bound under Options > Controls > Gameplay: enter the nearest garage, and drive out. Handy when the car cannot drive itself to the door.
- Career mode: only money is wired up. The garage does not know about career's own parts inventory.
- More garages can be added in `lua/ge/extensions/slrr/garageSites.lua` (parking spot, direction, door and wall distances).

## Source layout

| File | Job |
| --- | --- |
| `lua/ge/extensions/slrr/garage.lua` | state machine: door trigger, drive-in, garage, catalog, drive out |
| `lua/ge/extensions/slrr/garageParts.lua` | parts tree, shelf, catalog, money, hidden pre-loading |
| `lua/ge/extensions/slrr/garagePicker.lua` | finds the part under the cursor |
| `lua/ge/extensions/slrr/garageCamera.lua` | drive-in and orbit camera |
| `lua/ge/extensions/slrr/garageDamage.lua`, `lua/vehicle/extensions/slrrGarageVeh.lua` | damage that survives rebuilding the car |
| `lua/ge/extensions/slrr/garageMeshes.lua` | reads part models for the 3D previews |
| `lua/ge/extensions/slrr/garageStudio.lua` | optional photographed previews (off by default) |
| `lua/ge/extensions/slrr/garageCatalog.lua`, `garageSettings.lua` | catalog chapters, settings |
| `ui/modules/apps/slrrGarage/app.js` | the garage screen |

Not affiliated with BeamNG GmbH or the makers of Street Legal Racing: Redline.

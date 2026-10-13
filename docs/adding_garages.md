# Adding garages and shops

Wrench Works reads its garages and shops from small JSON files, so a map mod can bring its own and a player can add or move points without touching the mod.

## The quick way: stand there and say so

Open the console (the `~` key), pick "GE - Lua", and:

| Do this | Run this |
| --- | --- |
| Park the car where it should stand in the garage, nose pointing **in** (away from the door) | `slrr_garage.addGarageHere("Joe's Garage")` |
| Drive to the doorway of that garage and stop in the opening | `slrr_garage.setDoorHere()` |
| Stop where customers of a shop should stop | `slrr_garage.addShopHere("Joe's Tyres", "Wheels and tyres", {"running/rims_f", "running/rims_r", "running/tyres_f", "running/tyres_r"})` |
| Read the files again after editing one by hand | `slrr_garage.reloadSites()` |

Each of these works at once and writes to `settings/slrr_garage/sites.json` in your BeamNG user folder (`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current`). Running `addGarageHere` or `addShopHere` again with the same name moves that point.

A shop added without a list (`slrr_garage.addShopHere("Joe's Parts")`) sells everything.

## Shipping points with a map mod

Copy what the commands wrote into a file of your own inside your mod:

```
your_mod.zip
  wrench_works/sites/your_mod.json
```

Any file name will do; every `.json` in `wrench_works/sites/` is read. The player's own `settings/slrr_garage/sites.json` is read last, so players can still move or remove your points.

## The file

The top level is the map's folder name (the name under `levels/`). Positions are world coordinates in metres.

```json
{
  "my_map": {
    "garages": [
      {
        "id": "joes_garage",
        "name": "Joe's Garage",
        "spot": [904.5, -546.3, 163.65],
        "dir": [0.993, -0.12],
        "doorDist": -7,
        "halfWidth": 3.5,
        "backDist": 5,
        "ceiling": 4.5,
        "exit": "reverse"
      }
    ],
    "shops": [
      {
        "id": "joes_tyres",
        "name": "Joe's Tyres",
        "trade": "Wheels and tyres",
        "pos": [-582.1, 136.4, 101.2],
        "sells": ["running/rims_f", "running/rims_r", "running/tyres_f", "running/tyres_r", "running/hubs"]
      }
    ]
  }
}
```

An entry whose `id` matches an existing garage or shop **replaces** it, including the ones that come with Wrench Works; that is how a point is moved. `"remove": true` with an `id` takes one away.

### Garage fields

A garage is described along its own axis. `spot` is where the car is parked, on the floor. `dir` points from the front door into the building. Every distance is measured from the spot along that axis: negative is towards the street, positive is deeper into the building.

| Field | Meaning | If left out |
| --- | --- | --- |
| `id` | a name of your own, unique on the map | required |
| `name` | what the marker and the garage screen call it | the id |
| `spot` | `[x, y, z]` where the car stands, on the floor | required |
| `dir` | `[x, y]` the way the parked car faces: into the garage | required |
| `doorDist` | where the front door is; negative, e.g. `-7` is 7 m behind the car | `-7` |
| `halfWidth` | half the width of the room the camera may move in | `3.5` |
| `backDist` | how far the room goes on past the spot | `5` |
| `ceiling` | height of the room | `4.5` |
| `exit` | how a car that came in by the front door leaves: `"reverse"`, `"through"` or `"side"` | `"reverse"` |
| `viewYaw` | the angle, in degrees, the working camera starts at; change it when a pillar is in the way | `-145` |
| `filmAlong`, `filmSide` | where the camera stands for the drive-in, along the axis, and which wall (`1` or `-1`) | worked out from the room |
| `radio` | `[along, right, up]` where the radio stands | a back corner, 1.2 m up |

`exit` decides what the garage's second door is:

- `"reverse"`: there is one door. The car backs out the way it came.
- `"through"`: a back door on the same axis. Needs `backDoorDist` (positive: how far past the spot the back door is). Cars can come in by either door.
- `"side"`: a door in the left wall, reached by a quarter turn. Needs `exitTurnAlong` (where the turn starts), `exitRadius` (radius of the turn; the door is centred on `exitTurnAlong + exitRadius`), `sideDoorLeft` (how far left of the axis the side door is), `exitLeft` (how far left the drive out ends) and `exitClear` (left of this the car counts as outside).

If a second door is asked for but its numbers are missing, the garage falls back to `"reverse"` and says so in the log.

### Shop fields

| Field | Meaning | If left out |
| --- | --- | --- |
| `id` | a name of your own, unique on the map | required |
| `name` | the shop's name | the id |
| `trade` | the line under its name, e.g. "Wheels and tyres" | "Parts" |
| `pos` | `[x, y, z]` where customers stop | required |
| `sells` | catalog chapters (`"running/rims_f"`) or whole sections (`"engine"`) | everything |
| `yard` | `true` makes it a used-parts yard: a daily pick of everything, cheap and bent | `false` |

### Catalog sections and chapters

`engine`: `blocks`, `internals`, `intake`, `exhaust`, `fuel`, `forced`, `nitrous`, `management`, `transmission`, `clutch`, `cooling`, `mounts`

`body`: `shells`, `bumpers_f`, `bumpers_r`, `hoods`, `fenders`, `doors`, `trunk`, `roof`, `glass`, `lights_f`, `lights_r`, `bulbs`, `mirrors`, `wings`, `aero`, `chassis`, `plates`, `electrics`, `race`, `misc`

`running`: `suspension_f`, `suspension_r`, `shocks_f`, `shocks_r`, `bars`, `steering`, `brakes_f`, `brakes_r`, `brakes`, `rims_f`, `rims_r`, `tyres_f`, `tyres_r`, `hubs`, `differentials`, `driveline`

`interior`: `steering`, `dash`, `shifter`, `seats_f`, `seats_r`, `trim`, `extras`

`paint`: `skins`, `interior`, `plates`

Write a chapter as `section/chapter`, for example `"body/hoods"`.

## If something does not show up

Mistakes in a file are reported in the game's log (`beamng.log` in the user folder), on lines tagged `slrr_garage`: which file, which entry, and what is wrong with it. A file that is not valid JSON is skipped whole.

# Maps: building, hand-editing and markers

Every map is built in code by a builder module in `src/server/MapBuilders`, using
anchored parts and Terrain. There are no binary map files in the repository. At server
start, `WorldService` builds any map that isn't already in the place. You can also build
one into Workspace yourself to look at it, save it or hand-edit it.

| Map | Builder | Parts | Used by |
|-----|---------|------:|---------|
| The Spire (hub) | `HubBuilder` | 4677 | the hub (`Workspace.Hub`) |
| First Light | `FirstLightBuilder` | 1795 | story mission 1 |
| Sunken Relay | `SunkenRelayBuilder` | 1668 | story mission 2 |
| The Hollow Dark | `HollowDarkBuilder` | 861 + terrain caves | story mission 3 |
| Hollow Spire | `HollowSpireBuilder` | 859 | the Nightfall |
| Vault of Echoes | `VaultOfEchoesBuilder` | 1232 | the raid |

The budget is 15,000 parts per map. `Maps.spec` checks it, along with anchoring and every
marker the activity configs need.

## Building a map in Studio (command bar)

Open **View → Command Bar** and paste one line. With Rojo syncing, or in a place built
from this repository, the modules are in `ServerScriptService.MapBuilders`.

```lua
-- Builds the map into Workspace with its terrain, selects it and prints the part count:
require(game.ServerScriptService.MapBuilders.Generate)("FirstLight")

-- The same for any map: "Hub", "FirstLight", "SunkenRelay", "HollowDark", "HollowSpire", "VaultOfEchoes"
require(game.ServerScriptService.MapBuilders.Generate)("VaultOfEchoes")

-- Just the Model, no terrain and not parented (for your own scripts):
local model = require(game.ServerScriptService.MapBuilders.FirstLightBuilder).Build()
model.Parent = workspace

-- Fill in or clear a map's terrain (its invisible recipe parts in the Terrain folder):
require(game.ServerScriptService.MapBuilders.MapKit).ApplyTerrain(workspace.FirstLight)
require(game.ServerScriptService.MapBuilders.MapKit).ClearTerrain(workspace.FirstLight)
```

Maps are built at the origin. In a running game, each activity copy is moved to its own
slot at X = 5000 × slot, so building one in Workspace doesn't collide with play.

## Keeping a hand-edited version

1. Build it with `Generate` (above) and edit it: move, resize, recolor or add parts.
2. **Hub:** leave it in Workspace named `Hub`. `WorldService` uses an existing
   `Workspace.Hub` instead of generating one.
3. **Activity map:** first clear its preview terrain (`MapKit.ClearTerrain`, above),
   then move the Model into `ServerStorage.Activities`, keeping its name
   (`FirstLight`, `HollowSpire`...). `WorldService` only generates the maps that aren't
   there, and each activity copy gets its terrain from the map's `Terrain` folder
   wherever the copy is placed.
4. Save the place. Rojo only syncs code folders, so your map stays in the place file.
   A map in the place overrides later builder changes; delete it to go back to the
   generated one.

The game logic only reads the **Markers** folder, the **Gates** folder, a few attributes
and tags. Everything in `Geometry` is scenery you can change freely. After editing, run a
quick check in Studio: `/launch <map>`, then `/zone 1` … `/zone n` and watch for warnings
in the Output window. On the command line, `lune run tests/run Maps` checks the
generated maps (a hand-edited map in a place file isn't covered).

### Which maps are worth hand-editing

- **The Spire (hub):** the best candidate. It's pure scenery apart from `HubSpawn`, the
  range dummies and the area boxes, and it's the first thing players see.
- **First Light and Sunken Relay:** good candidates for dressing (props, lighting,
  terrain paint). Keep the zone layout; the markers' positions are what the missions
  depend on.
- **Hollow Spire (Nightfall):** dress it freely, but keep `CollapseFloor` (the model that
  falls away at 33%) inside the arena, and keep the `Chest` marker on solid floor.
- **The Hollow Dark:** its caves are Terrain carved by recipe parts (fill rock, carve
  Air, refill the floors, in `TerrainOrder`). Reshape a cave by moving or resizing
  those invisible parts in `Terrain`, not by editing the voxels. Voxel edits are lost
  because each copy rebuilds its terrain from the recipes.
- **Vault of Echoes:** edit with care. The Descent's platform gaps are tuned for jumps
  (movers and gaps), and the Silent Hall's lasers have timings. Dressing (lights,
  trim, statues) is safe; moving platforms is not.

## Model layout

```
<MapName> (Model, attribute KillY)
  Geometry/   everything you see and stand on
  Markers/    invisible, non-colliding parts the code finds by name
  Gates/      zone gates Gate_<ZoneId> (Models with a GateStyle attribute)
  Doors/      legacy force-field doors (empty in the current maps)
  Terrain/    invisible recipe parts: TerrainShape, TerrainMaterial, TerrainOrder
```

- **KillY** (model attribute): players below `origin.Y + KillY` are put back at their
  checkpoint (jumping puzzles, chasms); enemies below it die, and a falling boss is put
  back on its `BossSpawn`.
- **Gates** (`MapKit.Gate`): `GateStyle` `Door` slides up, `Shield` fades, `Bridge`
  (built see-through and non-solid) turns solid. MissionService opens `Gate_<ZoneId>`
  when that zone is cleared.
- **Movers** (tag `LL_Mover`): attributes `MoveOffset` (Vector3), `MovePeriod`,
  `MoveDwell`, `MovePhase`. Clients animate them from server time, so riders are
  carried smoothly.
- **Lasers** (tag `LL_Laser`): attributes `Damage`, and for blinking ones
  `LaserPeriod`, `LaserOn` (fraction of the period) and `LaserPhase`. A laser can also
  be a mover (sweeping walls). The server works out where each laser is from the same
  timing and burns players inside it.
- **Spinners** (tag `LL_Spin`: `SpinAxis`, `SpinSpeed`, `SpinCenter`) and flyers
  (`FlightCenter`, `FlightRadius`, `FlightSpeed`, `FlightPhase`) are decoration.

## Marker reference

Common to every activity map:

| Marker | Meaning |
|--------|---------|
| `Spawns/PlayerStart` | where the fireteam appears, facing the marker's front |
| `Checkpoints/CP_<ZoneId>` | respawn point once that zone is entered |
| `Objectives/<Name>` | travel targets and hold rings (a box sized to the area: being inside counts), consoles (`Interact`), and `<Name>_1..n` for things to destroy |
| `EnemySpawns/<Group>/<Group>_n` | where a wave of that group spawns (default group = the zone's Id); points hidden from players and far enough away are picked first |
| `BossArena/BossSpawn` | the boss (and where a fallen boss is put back) |
| `BossArena/Ammo_n` | heavy ammo drops during the fight |
| `BossArena/Pylon_n` | objects to destroy during a Pylons immune phase |
| `BossArena/Teleport_n` | where a teleporting boss appears |
| `BossArena/Safe_n` | the nova's safe circles |
| `BossArena/Chest` | where the loot chest appears (default: where the boss died) |

Maps with several bosses (the raid) use one folder per arena (`GateArena`,
`ChamberArena`, `ThroneArena`) instead of `BossArena`.

### First Light (`FirstLight`, KillY -60)

Path along +Z, ground at Y 0, snow terrain.

| Zone (Z range) | Markers | Gate |
|----------------|---------|------|
| CrashSite (-80..140): the wreck, tree line | `CP_CrashSite`, `Wreck`, `EnemySpawns/CrashSite_1..7` | `Gate_CrashSite` Shield at z 140 |
| Village (140..440): Frostfall street, two watch houses | `CP_Village`, `VillageGate`, `EnemySpawns/Village_1..7`, `VillageRoofs_1..3` (snipers) | `Gate_Village` Door at z 440 |
| Outpost (440..620): walled courtyard, watchtowers | `CP_Outpost`, `Uplink` (hold ring), `EnemySpawns/Outpost_1..5`, `OutpostTurrets_1..4` | `Gate_Outpost` Door at z 620 |
| Reactor (620..760): bunker hall around the core | `CP_Reactor`, `Regulator_1..3`, `EnemySpawns/Reactor_1..5` | `Gate_Reactor` Bridge over the chasm |
| ScrapPit (815..945): round platform over the abyss | `CP_ScrapPit`, `EnemySpawns/ScrapPit_1..6`, `BossArena/BossSpawn`, `Ammo_1..3` | none |

### Sunken Relay (`SunkenRelay`, KillY -30)

Path along +Z; the ocean is to the south; the tower is 90 × 90 (x -45..45, z 305..395).

| Zone | Markers | Gate |
|------|---------|------|
| Beach (z -90..60) | `CP_Beach`, `Dunes`, `EnemySpawns/Beach_1..6` | `Gate_Beach` Shield in the sea wall (z 60) |
| Market (z 60..305): streets under 2 studs of water | `CP_Market`, `EnemySpawns/Market_1..7`, `MarketBalconies_1..3` | `Gate_Market` Door into the tower (z 305) |
| LowerDeck (tower, Y 1) | `CP_LowerDeck`, `EnemySpawns/LowerDeck_1..5` | `Gate_LowerDeck` Door on the east-stair landing |
| SignalDeck (tower, Y 31) | `CP_SignalDeck`, `Jammer_1..3`, `EnemySpawns/SignalDeck_1..5` | `Gate_SignalDeck` Shield on the west-stair landing |
| Crown (tower roof, Y 61) | `CP_Crown`, `EnemySpawns/Crown_1..6`, `BossArena/BossSpawn`, `Ammo_1..3`, `Pylon_1..3` | none |

### The Hollow Dark (`HollowDark`, KillY -80)

Path along +Z; the caves are carved Terrain with floors at Y 0.

| Zone | Markers | Gate |
|------|---------|------|
| Mouth (z -95..95): the pale woods | `CP_Mouth`, `CaveMouth`, `EnemySpawns/Mouth_1..7` | `Gate_Mouth` Shield (z 96) |
| Caverns (z 96..330): crystals, ledges | `CP_Caverns`, `CavernHeart`, `EnemySpawns/Caverns_1..7`, `CavernLedges_1..3` | `Gate_Caverns` Bridge over the chasm (z 330..372) |
| Barracks (z 372..560) | `CP_Barracks`, `WardSeal` (hold E), `EnemySpawns/Barracks_1..6` | `Gate_Barracks` Door (z 561) |
| Ritual (z 590..730): round chamber under an oculus | `CP_Ritual`, `RitualCrystal_1..3`, `EnemySpawns/Ritual_1..6`, `BossArena/BossSpawn`, `Ammo_1..3`, `Pylon_1..3`, `Teleport_1..4` | none |

### Hollow Spire (`HollowSpire`, the Nightfall, KillY -40)

Path along +Z; canyon floor at Y 0; the arena is up the grand stairs at Y 60.

| Zone | Markers | Gate |
|------|---------|------|
| Canyon (z -40..300) | `CP_Canyon`, `CanyonBend`, `EnemySpawns/Canyon_1..7`, `CanyonLedges_1..4` (turrets) | `Gate_Canyon` Shield (z 300) |
| Gate (z 300..420): plaza before the wall | `CP_Gate`, `Generator_1..3`, `EnemySpawns/Gate_1..6`, `GateWall_1..3` (snipers) | `Gate_Gate` Door |
| Halls (z 424..627) | `CP_Halls`, `LiftControls` (hold ring), `EnemySpawns/Halls_1..6`, `HallTurrets_1..4` | `Gate_Halls` Door (z 627) |
| Summit (z 725..835, Y 60): the Spire Crown | `CP_Summit`, `EnemySpawns/Summit_1..6`, `BossArena/BossSpawn`, `Chest`, `Ammo_1..3`, `Pylon_1..3` | none |

The arena's middle floor is the Model `CollapseFloor`. It flashes and falls at 33%.

### Vault of Echoes (`VaultOfEchoes`, the raid, KillY -120)

Upper level at Y 0, lower level at Y -30; path along +Z.

| Encounter / zone | Markers | Gate |
|------------------|---------|------|
| The Gate (z 0..170): round arena, r 70 | `CP_Gate`, `GateEntry`, `EnemySpawns/Gate_1..8`, `GateArena/BossSpawn`, `Ammo_1..3`, `Chest`; the echo plates `Plate_1..3` are visible parts (found by name anywhere in the map) | `Gate_Gate` Door (z 168) |
| The Descent (z 175..410): jumping puzzle down to Y -30 | `CP_Descent`, `DescentEnd`; the platforms (some `LL_Mover`) | `Gate_Descent` Shield (z 410) |
| The Echo Chamber: hub at (0, -30, 480), rooms west, east, north | `CP_Chamber`, `ChamberEntry`, `EnemySpawns/Chamber_1..8`, `ChamberArena/BossSpawn`, `EchoWell` (deposit zone), `Room_1..3` (Bearers), `Ammo_1..3`, `Chest` | `Gate_Chamber` Door in the north room (z 570) |
| The Silent Hall (z 570..770): lasers and a patrol | `CP_SilentHall`, `HallEnd`, `EnemySpawns/HallPatrol_1..6` (the patrol route, in order); the lasers are `LL_Laser` parts | `Gate_SilentHall` Shield |
| The Throne: round arena, r 65, at (0, -30, 850) | `CP_Throne`, `ThroneEntry`, `EnemySpawns/Throne_1..6`, `ThroneArena/BossSpawn`, `Safe_1..4`, `Pylon_1..3`, `Teleport_1..3`, `Ammo_1..3`, `Chest` | none |

### The Spire (`Hub`, KillY -120)

| Marker | Meaning |
|--------|---------|
| `Spawns/HubSpawn` | where players appear |
| `Range/Dummy_1..3` | range targets at 15, 30 and 55 studs |
| `Range/RangeZone` | weapons are drawn inside this box |
| `Areas/Area_Courtyard`, `Area_CommandDeck`, `Area_Bazaar`, `Area_Hangar`, `Area_Range` | boxes whose `DisplayName` pops up on entry |

## A new map

Copy the closest builder, keep the folder layout and marker names above, and register
the map name in `WorldConfig.Maps`, a lighting preset in `WorldConfig.Lighting`, loading
art in `AssetIds.Images.Loading` and a placeholder palette in
`PresentationConfig.Loading.Palettes`. Then point an activity's `Map` at it. The tests
list any marker a mission needs that the map doesn't have.
